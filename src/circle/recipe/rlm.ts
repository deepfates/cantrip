import { AnyMessage } from "../../crystal/messages";
import { BaseChatModel } from "../../crystal/crystal";
import {
  JsAsyncContext,
} from "../medium/js/async_context";
import {
  registerRlmFunctions,
  safeStringify,
  defaultProgress,
} from "./rlm_tools";
import type { RlmProgressCallback } from "./rlm_tools";
import { getRlmSystemPrompt, getRlmMemorySystemPrompt } from "./rlm_prompt";
import { UsageTracker } from "../../crystal/tokens/usage";
import type { Entity } from "../../cantrip/entity";
import { cantrip } from "../../cantrip/cantrip";
import { js as jsMedium, getJsMediumSandbox } from "../medium/js";
import { Circle } from "../circle";
import { max_turns, require_done } from "../ward";
import { call_entity as call_entity_gate, call_entity_batch as call_entity_batch_gate } from "../gate/builtin/call_entity_gate";
import { done_for_medium } from "../gate/builtin/done";
import type { BoundGate } from "../gate/gate";
import { Loom, MemoryStorage } from "../../loom";

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
  browserContext?: import("../medium/browser/context").BrowserContext;
  /** Progress callback for sub-agent activity. Defaults to console.error logging. */
  onProgress?: RlmProgressCallback;
  /** Optional shared loom — when provided, child records into parent's loom instead of creating its own. */
  loom?: Loom;
  /** Parent turn ID — the parent turn that spawned this child entity. */
  parent_turn_id?: string;
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
    loom: parentLoom,
    parent_turn_id,
  } = options;

  // 1. Create JS medium with context as initial state
  const medium = jsMedium({ state: { context } });

  // Resolve the loom early so it's available for gate construction.
  // When a parent loom is provided, the child records into it (unified tree).
  // Otherwise, create an ephemeral loom (backward compat / top-level agents).
  const loom = parentLoom ?? new Loom(new MemoryStorage());

  // 2. Build gates array — done gate (submit_answer) + call_entity gate (llm_query)
  // entityRef is populated after entity creation (step 7); execute() is only called
  // during entity.cast(), so the ref is always populated by then.
  const entityRef: { current: Entity | null } = { current: null };
  const progress = onProgress ?? defaultProgress(depth);
  const gates: BoundGate[] = [done_for_medium()];
  const entityGate = call_entity_gate({
    crystal: subLlm,
    sub_crystal: subLlm,
    max_depth: maxDepth,
    depth,
    usage,
    parent_context: context,
    onProgress: progress,
    browserContext,
    loom,
    getCurrentTurnId: () => entityRef.current?.lastTurnId ?? null,
  });
  if (entityGate) gates.push(entityGate);
  const batchGate = call_entity_batch_gate({
    crystal: subLlm,
    sub_crystal: subLlm,
    max_depth: maxDepth,
    depth,
    usage,
    parent_context: context,
    onProgress: progress,
    browserContext,
    loom,
    getCurrentTurnId: () => entityRef.current?.lastTurnId ?? null,
  });
  if (batchGate) gates.push(batchGate);

  // 3. Init medium with gates so the sandbox exists and gates are registered as host functions.
  // Circle's lazy init will be a no-op since medium is already initialized.
  await medium.init(gates, dependency_overrides || null);
  const sandbox = getJsMediumSandbox(medium)!;

  // 4. Build Circle with the JS medium, gates, and wards
  const circle = Circle({
    medium,
    gates,
    wards: [max_turns(20), require_done()],
  });

  // 5. Analyze the context structure and generate the System Prompt.
  // Uses circle.capabilityDocs() so the prompt reflects the circle's actual capabilities.
  const metadata = analyzeContext(context);
  const systemPrompt = getRlmSystemPrompt({
    contextType: metadata.type,
    contextLength: metadata.length,
    contextPreview: metadata.preview,
    gates,
    capabilityDocs: circle.capabilityDocs(),
    hasBrowser: !!browserContext,
    browserAllowedFunctions: browserContext
      ? new Set(browserContext.getAllowedFunctions())
      : undefined,
  });

  // 6. Register remaining RLM Host Functions (browser, etc.)
  // When gates exist (depth < maxDepth), the medium already registered llm_query and llm_batch.
  // onLlmQuery is only used as a fallback when skipLlmQuery is false (depth >= maxDepth).
  await registerRlmFunctions({
    sandbox,
    context,
    depth,
    browserContext,
    onProgress,
    skipLlmQuery: !!entityGate,
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

        const res = await subLlm.query([
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
        return await child.entity.cast(query);
      } finally {
        child.sandbox.dispose();
      }
    },
  });

  // 7. Create Entity via cantrip API with shared usage tracker and folding
  const spell = cantrip({
    crystal: llm,
    call: { system_prompt: systemPrompt, hyperparameters: { tool_choice: "auto" } },
    circle,
    dependency_overrides: dependency_overrides.size ? dependency_overrides : null,
    usage_tracker: usage,
    loom,
    parent_turn_id,
    folding_enabled: true,
    folding: {
      enabled: true,
      threshold_ratio: 0.75,
      summary_prompt: "Summarize the key findings and decisions from the conversation so far. Be concise but preserve important details, data values, and conclusions.",
      recent_turns_to_keep: 5,
    },
  });
  const entity = spell.invoke();
  entityRef.current = entity;

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
  browserContext?: import("../medium/browser/context").BrowserContext;
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

  // 2. Build gates array — done gate (submit_answer) + call_entity gate (llm_query)
  const gates: BoundGate[] = [done_for_medium()];
  const entityGate = call_entity_gate({
    crystal: subLlm,
    sub_crystal: subLlm,
    max_depth: maxDepth,
    depth: 0, // Memory agent is depth 0
    usage,
    parent_context: context,
    onProgress,
  });
  if (entityGate) gates.push(entityGate);
  const batchGate = call_entity_batch_gate({
    crystal: subLlm,
    sub_crystal: subLlm,
    max_depth: maxDepth,
    depth: 0,
    usage,
    parent_context: context,
    onProgress,
  });
  if (batchGate) gates.push(batchGate);

  // 3. Init medium with gates so sandbox exists and gates are registered as host functions
  await medium.init(gates, null);
  const sandbox = getJsMediumSandbox(medium)!;

  // 4. Build Circle with the JS medium, gates, and wards
  const circle = Circle({
    medium,
    gates,
    wards: [max_turns(20), require_done()],
  });

  // 5. Generate system prompt that explains the memory feature.
  // Uses circle.capabilityDocs() so the prompt reflects the circle's actual capabilities.
  const dataMetadata = data ? analyzeContext(data) : null;
  const systemPrompt = getRlmMemorySystemPrompt({
    hasData: !!data,
    dataType: dataMetadata?.type,
    dataLength: dataMetadata?.length,
    dataPreview: dataMetadata?.preview,
    windowSize,
    gates,
    capabilityDocs: circle.capabilityDocs(),
    hasBrowser: !!browserContext,
    browserAllowedFunctions: browserContext
      ? new Set(browserContext.getAllowedFunctions())
      : undefined,
  });

  // 6. Register remaining RLM functions (browser, etc.)
  // When gates exist (maxDepth > 0), the medium already registered llm_query and llm_batch.
  // onLlmQuery is only used as a fallback when skipLlmQuery is false (maxDepth <= 0).
  await registerRlmFunctions({
    sandbox,
    context,
    depth: 0,
    browserContext,
    onProgress,
    skipLlmQuery: !!entityGate,
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

        const res = await subLlm.query([
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
        return await child.entity.cast(query);
      } finally {
        child.sandbox.dispose();
      }
    },
  });

  // 7. Create Entity via cantrip API with shared usage tracker and folding
  const loom = new Loom(new MemoryStorage());
  const spell = cantrip({
    crystal: llm,
    call: { system_prompt: systemPrompt, hyperparameters: { tool_choice: "auto" } },
    circle,
    dependency_overrides: null,
    usage_tracker: usage,
    loom,
    folding_enabled: true,
    folding: {
      enabled: true,
      threshold_ratio: 0.75,
      summary_prompt: "Summarize the key findings and decisions from the conversation so far. Be concise but preserve important details, data values, and conclusions.",
      recent_turns_to_keep: windowSize,
    },
  });
  const entity = spell.invoke();

  // 8. Memory management function — uses entity.history/load_history
  //
  // Folding manages context window size via LLM summaries (§6.8).
  // manageMemory migrates old turns into context.history where the entity
  // can search them via JS code in the sandbox. Both are needed:
  // - Folding compresses messages in place (threshold-based, automatic)
  // - manageMemory moves messages to sandbox state (called by the user after each turn)
  // These don't conflict — folding may have already compressed some messages,
  // and manageMemory handles whatever messages remain beyond windowSize.
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
