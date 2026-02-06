import { Agent, AnyMessage } from "../agent/service";
import { BaseChatModel } from "../llm/base";
import {
  JsAsyncContext,
  createAsyncModule,
} from "../tools/builtin/js_async_context";
import { js_rlm, getRlmSandbox, registerRlmFunctions } from "./tools";
import { getRlmSystemPrompt, getRlmMemorySystemPrompt } from "./prompt";
import { UsageTracker } from "../tokens/usage";

export type RlmOptions = {
  llm: BaseChatModel;
  context: unknown;
  subLlm?: BaseChatModel;
  maxDepth?: number;
  depth?: number;
  usage?: UsageTracker;
  dependency_overrides?: Map<any, any>;
  /** Number of recent turns to keep in active prompt (rest moves to context.history) */
  windowSize?: number;
};

/**
 * Factory to create an RLM-enabled Agent.
 *
 * An RLM Agent is a standard Agent equipped with:
 * 1. A persistent JsAsyncContext sandbox containing the 'context' data.
 * 2. A 'js' tool that returns metadata-only results to prevent context window bloat.
 * 3. Specialized host functions for recursive delegation and termination.
 *
 * Purity: The agent cannot use 'done' or 'final_answer' tools. It MUST use
 * the 'submit_answer()' function from within the sandbox to finish the task.
 */
export async function createRlmAgent(
  options: RlmOptions,
): Promise<{ agent: Agent; sandbox: JsAsyncContext }> {
  const {
    llm,
    context,
    subLlm = llm,
    maxDepth = 2,
    depth = 0,
    usage = new UsageTracker(),
    dependency_overrides = new Map(),
  } = options;

  // 1. Prepare Sandbox with a recursion-safe WASM module instance
  const module = await createAsyncModule();
  const sandbox = await JsAsyncContext.create({ module });

  // 2. Analyze the context structure to generate the System Prompt
  const metadata = analyzeContext(context);
  const systemPrompt = getRlmSystemPrompt({
    contextType: metadata.type,
    contextLength: metadata.length,
    contextPreview: metadata.preview,
  });

  // 3. Register RLM Host Functions (The Recursive Bridge)
  // This must be awaited to ensure the sandbox is fully hydrated before the Agent starts.
  await registerRlmFunctions({
    sandbox,
    context,
    onLlmQuery: async (query, subContext) => {
      // If subContext is omitted, the child receives the current parent context
      const contextToPass = subContext !== undefined ? subContext : context;

      if (depth >= maxDepth) {
        // Fallback to a plain LLM completion at the maximum recursion depth level
        // Truncate context to avoid blowing up the prompt at leaf level
        const contextStr =
          typeof contextToPass === "string"
            ? contextToPass
            : JSON.stringify(contextToPass, null, 2);
        const truncated =
          contextStr.length > 10000
            ? contextStr.slice(0, 10000) + "\n... [truncated]"
            : contextStr;

        const res = await subLlm.ainvoke([
          {
            role: "user",
            content: `Task: ${query}\n\nContext Snippet:\n${truncated}`,
          },
        ]);
        return res.content ?? "";
      }

      // Recursive step: Spawn a nested RLM agent at the next depth level
      const child = await createRlmAgent({
        llm: subLlm,
        subLlm,
        context: contextToPass,
        maxDepth,
        depth: depth + 1,
        usage,
        dependency_overrides,
      });

      try {
        return await child.agent.query(query);
      } finally {
        // Clean up the child sandbox to reclaim WASM memory
        child.sandbox.dispose();
      }
    },
  });

  // 4. Initialize the Agent with RLM-specialized configuration
  const overrides = new Map(dependency_overrides);
  overrides.set(getRlmSandbox, () => sandbox);

  const agent = new Agent({
    llm,
    tools: [js_rlm], // Only the JS tool is provided. submit_answer() is used for exit.
    system_prompt: systemPrompt,
    dependency_overrides: overrides,
    max_iterations: 20, // RLM levels usually have shorter reasoning horizons
    usage_tracker: usage,
    require_done_tool: true, // This combined with only having 'js' forces the sandbox exit
  });

  return { agent, sandbox };
}

/**
 * Extracts structural metadata from the context variable for the LLM.
 */
function analyzeContext(context: unknown): {
  type: string;
  length: number;
  preview: string;
} {
  if (typeof context === "string") {
    return {
      type: "String (Explore via context.match(), context.includes(), context.slice())",
      length: context.length,
      preview: context.slice(0, 200),
    };
  }

  if (Array.isArray(context)) {
    return {
      type: `Array [${context.length} items] (Explore via context.filter(), context.find(), context[0])`,
      length: JSON.stringify(context).length,
      preview: JSON.stringify(context.slice(0, 3)),
    };
  }

  if (typeof context === "object" && context !== null) {
    const keys = Object.keys(context);
    return {
      type: `Object {${keys.length} keys} (Explore via Object.keys(context), context.property)`,
      length: JSON.stringify(context).length,
      preview: JSON.stringify(context).slice(0, 200),
    };
  }

  return {
    type: typeof context,
    length: String(context).length,
    preview: String(context).slice(0, 200),
  };
}

export type RlmMemoryOptions = {
  llm: BaseChatModel;
  /** User-provided data context (optional) */
  data?: unknown;
  subLlm?: BaseChatModel;
  maxDepth?: number;
  usage?: UsageTracker;
  /** Number of user turns to keep in active prompt window */
  windowSize: number;
};

export type RlmMemoryAgent = {
  agent: Agent;
  sandbox: JsAsyncContext;
  /** Call after each turn to manage the sliding window */
  manageMemory: () => void;
};

/**
 * Creates an RLM agent with auto-managed conversation history.
 *
 * The context object has two parts:
 * - `context.data`: User-provided data (optional)
 * - `context.history`: Older messages that have been moved out of the active prompt
 *
 * After windowSize user turns, older messages are moved from the agent's
 * active message history into context.history, where the agent can search them.
 */
export async function createRlmAgentWithMemory(
  options: RlmMemoryOptions,
): Promise<RlmMemoryAgent> {
  const {
    llm,
    data,
    subLlm = llm,
    maxDepth = 2,
    usage = new UsageTracker(),
    windowSize,
  } = options;

  // The unified context object
  const context: { data: unknown; history: AnyMessage[] } = {
    data: data ?? null,
    history: [],
  };

  // Track user turns for windowing
  let userTurnCount = 0;

  // 1. Prepare Sandbox
  const module = await createAsyncModule();
  const sandbox = await JsAsyncContext.create({ module });

  // 2. Generate system prompt that explains the memory feature
  const dataMetadata = data ? analyzeContext(data) : null;
  const systemPrompt = getRlmMemorySystemPrompt({
    hasData: !!data,
    dataType: dataMetadata?.type,
    dataLength: dataMetadata?.length,
    dataPreview: dataMetadata?.preview,
    windowSize,
  });

  // 3. Register RLM functions with the unified context
  // Memory agent is always at depth 0, children start at depth 1
  await registerRlmFunctions({
    sandbox,
    context,
    onLlmQuery: async (query, subContext) => {
      const contextToPass = subContext !== undefined ? subContext : context;

      if (maxDepth <= 0) {
        // At max depth, fall back to plain LLM completion
        // Truncate context to avoid blowing up the prompt at leaf level
        const contextStr =
          typeof contextToPass === "string"
            ? contextToPass
            : JSON.stringify(contextToPass, null, 2);
        const truncated =
          contextStr.length > 10000
            ? contextStr.slice(0, 10000) + "\n... [truncated]"
            : contextStr;

        const res = await subLlm.ainvoke([
          {
            role: "user",
            content: `Task: ${query}\n\nContext:\n${truncated}`,
          },
        ]);
        return res.content ?? "";
      }

      // Spawn child RLM agent at depth 1
      const child = await createRlmAgent({
        llm: subLlm,
        subLlm,
        context: contextToPass,
        maxDepth,
        depth: 1, // Memory agent is depth 0, child is depth 1
        usage,
      });

      try {
        return await child.agent.query(query);
      } finally {
        child.sandbox.dispose();
      }
    },
  });

  // 4. Create agent
  const overrides = new Map();
  overrides.set(getRlmSandbox, () => sandbox);

  const agent = new Agent({
    llm,
    tools: [js_rlm],
    system_prompt: systemPrompt,
    dependency_overrides: overrides,
    max_iterations: 20,
    usage_tracker: usage,
    require_done_tool: true,
  });

  // 5. Memory management function
  const manageMemory = () => {
    // Keep slicing until active user count is within window
    while (true) {
      const activeUserCount = agent.messages.filter(
        (m) => m.role === "user",
      ).length;
      if (activeUserCount <= windowSize) break;
      // Find the end of the first turn (from first user message to next user message)
      const startIndex = agent.messages[0]?.role === "system" ? 1 : 0;
      let cutIndex = startIndex;

      // Find first user message
      while (
        cutIndex < agent.messages.length &&
        agent.messages[cutIndex].role !== "user"
      ) {
        cutIndex++;
      }

      if (cutIndex >= agent.messages.length) break;

      // Skip past the user message
      cutIndex++;

      // Find end of turn (next user message or end of messages)
      while (
        cutIndex < agent.messages.length &&
        agent.messages[cutIndex].role !== "user"
      ) {
        cutIndex++;
      }

      if (cutIndex <= startIndex) break;

      // Move messages to history
      const toMove = agent.messages.slice(startIndex, cutIndex);
      context.history.push(...toMove);

      // Remove from active messages (keep system prompt)
      agent.messages = [
        ...(startIndex === 1 ? [agent.messages[0]] : []),
        ...agent.messages.slice(cutIndex),
      ];
    }

    // Update sandbox with new context
    sandbox.setGlobal("context", context);
  };

  return { agent, sandbox, manageMemory };
}
