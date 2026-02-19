import { AnyMessage } from "../../../crystal/messages";
import { BaseChatModel } from "../../../crystal/crystal";
import {
  JsAsyncContext,
} from "./js_async_context";
import {
  registerRlmFunctions,
  safeStringify,
} from "./call_entity_tools";
import type { RlmProgressCallback } from "./call_entity_tools";
import { getRlmSystemPrompt, getRlmMemorySystemPrompt } from "./call_entity_prompt";
import { UsageTracker } from "../../../crystal/tokens/usage";
import { Entity } from "../../../cantrip/entity";
import { js as jsMedium, getJsMediumSandbox } from "../../medium/js";
import { Circle } from "../../circle";
import { max_turns, require_done } from "../../ward";

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
  /** Optional browser context — enables browser(code) host function in the sandbox. */
  browserContext?: import("./browser_context").BrowserContext;
  /** Progress callback for sub-agent activity. Defaults to console.error logging. */
  onProgress?: RlmProgressCallback;
};

/**
 * Factory to create an RLM-enabled Entity.
 *
 * An RLM Entity is a standard Entity equipped with:
 * 1. A persistent JsAsyncContext sandbox containing the 'context' data.
 * 2. A 'js' tool that returns metadata-only results to prevent context window bloat.
 * 3. Specialized host functions for recursive delegation and termination.
 *
 * Purity: The entity cannot use 'done' or 'final_answer' tools. It MUST use
 * the 'submit_answer()' function from within the sandbox to finish the task.
 *
 * Internally uses the cantrip API: Circle({ medium: js(...) }) + cantrip() + invoke().
 */
export async function createRlmAgent(
  options: RlmOptions,
): Promise<{ entity: Entity; sandbox: JsAsyncContext }> {
  const {
    llm,
    context,
    subLlm = llm,
    maxDepth = 2,
    depth = 0,
    usage = new UsageTracker(),
    dependency_overrides = new Map(),
    browserContext,
    onProgress,
  } = options;

  // 1. Create JS medium with context as initial state
  const medium = jsMedium({ state: { context } });

  // 2. Force medium initialization so we can access the sandbox
  await medium.init([], dependency_overrides || null);
  const sandbox = getJsMediumSandbox(medium)!;

  // 3. Analyze the context structure to generate the System Prompt
  const metadata = analyzeContext(context);
  const systemPrompt = getRlmSystemPrompt({
    contextType: metadata.type,
    contextLength: metadata.length,
    contextPreview: metadata.preview,
    hasRecursion: depth < maxDepth,
    hasBrowser: !!browserContext,
    browserAllowedFunctions: browserContext
      ? new Set(browserContext.getAllowedFunctions())
      : undefined,
  });

  // 4. Register RLM Host Functions (The Recursive Bridge)
  // submit_answer is already registered by the medium, but registerRlmFunctions
  // adds llm_query, llm_batch, and browser functions.
  await registerRlmFunctions({
    sandbox,
    context,
    depth,
    browserContext,
    onProgress,
    onLlmQuery: async (query, subContext) => {
      const contextToPass = subContext !== undefined ? subContext : context;

      if (depth >= maxDepth) {
        const contextStr =
          typeof contextToPass === "string"
            ? contextToPass
            : safeStringify(contextToPass, 2);
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
        if (res.usage) {
          usage.add(subLlm.model, res.usage);
        }
        return res.content ?? "";
      }

      const child = await createRlmAgent({
        llm: subLlm,
        subLlm,
        context: contextToPass,
        maxDepth,
        depth: depth + 1,
        usage,
        dependency_overrides,
        browserContext,
        onProgress,
      });

      try {
        return await child.entity.turn(query);
      } finally {
        child.sandbox.dispose();
      }
    },
  });

  // 5. Build Circle with the JS medium and wards
  const circle = Circle({
    medium,
    gates: [],
    wards: [max_turns(20), require_done()],
  });

  // 6. Create Entity via cantrip API with shared usage tracker
  const entity = new Entity({
    crystal: llm,
    call: {
      system_prompt: systemPrompt,
      hyperparameters: { tool_choice: "auto" },
      gate_definitions: [],
    },
    circle,
    dependency_overrides: dependency_overrides.size ? dependency_overrides : null,
    usage_tracker: usage,
  });

  return { entity, sandbox };
}

/**
 * Extracts structural metadata from the context variable for the LLM.
 */
export function analyzeContext(context: unknown): {
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
      length: safeStringify(context).length,
      preview: safeStringify(context.slice(0, 3)),
    };
  }

  if (typeof context === "object" && context !== null) {
    const keys = Object.keys(context);
    const serialized = safeStringify(context);
    return {
      type: `Object {${keys.length} keys} (Explore via Object.keys(context), context.property)`,
      length: serialized.length,
      preview: serialized.slice(0, 200),
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
  /** Optional browser context — enables browser(code) host function in the sandbox. */
  browserContext?: import("./browser_context").BrowserContext;
  /** Progress callback for sub-agent activity. Defaults to console.error logging. */
  onProgress?: RlmProgressCallback;
};

export type RlmMemoryAgent = {
  entity: Entity;
  sandbox: JsAsyncContext;
  /** Call after each turn to manage the sliding window */
  manageMemory: () => void;
};

/**
 * Creates an RLM entity with auto-managed conversation history.
 *
 * The context object has two parts:
 * - `context.data`: User-provided data (optional)
 * - `context.history`: Older messages that have been moved out of the active prompt
 *
 * After windowSize user turns, older messages are moved from the entity's
 * active message history into context.history, where the entity can search them.
 *
 * Uses Entity via cantrip API internally. The `manageMemory()` function uses
 * `entity.history` (read) and `entity.load_history()` (write) for sliding-window
 * memory management.
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
    browserContext,
    onProgress,
  } = options;

  // The unified context object
  const context: { data: unknown; history: AnyMessage[] } = {
    data: data ?? null,
    history: [],
  };

  // 1. Create JS medium with context as initial state
  const medium = jsMedium({ state: { context } });

  // 2. Force medium initialization so we can access the sandbox
  await medium.init([], null);
  const sandbox = getJsMediumSandbox(medium)!;

  // 3. Generate system prompt that explains the memory feature
  const dataMetadata = data ? analyzeContext(data) : null;
  const systemPrompt = getRlmMemorySystemPrompt({
    hasData: !!data,
    dataType: dataMetadata?.type,
    dataLength: dataMetadata?.length,
    dataPreview: dataMetadata?.preview,
    windowSize,
    hasBrowser: !!browserContext,
    browserAllowedFunctions: browserContext
      ? new Set(browserContext.getAllowedFunctions())
      : undefined,
  });

  // 4. Register RLM functions with the unified context
  // Memory agent is always at depth 0, children start at depth 1
  await registerRlmFunctions({
    sandbox,
    context,
    depth: 0,
    browserContext,
    onProgress,
    onLlmQuery: async (query, subContext) => {
      const contextToPass = subContext !== undefined ? subContext : context;

      if (maxDepth <= 0) {
        // At max depth, fall back to plain LLM completion
        const contextStr =
          typeof contextToPass === "string"
            ? contextToPass
            : safeStringify(contextToPass, 2);
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
        if (res.usage) {
          usage.add(subLlm.model, res.usage);
        }
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
        browserContext,
        onProgress,
      });

      try {
        return await child.entity.turn(query);
      } finally {
        child.sandbox.dispose();
      }
    },
  });

  // 5. Build Circle with the JS medium and wards
  const circle = Circle({
    medium,
    gates: [],
    wards: [max_turns(20), require_done()],
  });

  // 6. Create Entity via cantrip API with shared usage tracker
  const entity = new Entity({
    crystal: llm,
    call: {
      system_prompt: systemPrompt,
      hyperparameters: { tool_choice: "auto" },
      gate_definitions: [],
    },
    circle,
    dependency_overrides: null,
    usage_tracker: usage,
  });

  // 7. Memory management function — uses entity.history/load_history
  const manageMemory = () => {
    // Keep slicing until active user count is within window
    while (true) {
      let messages = entity.history; // read-only copy
      const activeUserCount = messages.filter(
        (m) => m.role === "user",
      ).length;
      if (activeUserCount <= windowSize) break;
      // Find the end of the first turn (from first user message to next user message)
      const startIndex = messages[0]?.role === "system" ? 1 : 0;
      let cutIndex = startIndex;

      // Find first user message
      while (
        cutIndex < messages.length &&
        messages[cutIndex].role !== "user"
      ) {
        cutIndex++;
      }

      if (cutIndex >= messages.length) break;

      // Skip past the user message
      cutIndex++;

      // Find end of turn (next user message or end of messages)
      while (
        cutIndex < messages.length &&
        messages[cutIndex].role !== "user"
      ) {
        cutIndex++;
      }

      if (cutIndex <= startIndex) break;

      // Move messages to history
      const toMove = messages.slice(startIndex, cutIndex);
      context.history.push(...toMove);

      // Remove from active messages (keep system prompt)
      messages = [
        ...(startIndex === 1 ? [messages[0]] : []),
        ...messages.slice(cutIndex),
      ];
      entity.load_history(messages); // write back
    }

    // Update sandbox with new context
    sandbox.setGlobal("context", context);
  };

  return { entity, sandbox, manageMemory };
}
