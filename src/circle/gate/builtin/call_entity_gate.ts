import type { BoundGate, GateDocs } from "../gate";
import type { BaseChatModel } from "../../../crystal/crystal";
import type { UsageTracker } from "../../../crystal/tokens/usage";
import type { RlmProgressCallback } from "../../recipe/rlm_tools";
import type { BrowserContext } from "../../medium/browser/context";
import type { Loom } from "../../../loom";

export type CallEntityGateOptions = {
  /** Crystal (LLM) for child entities */
  crystal: BaseChatModel;
  /** Crystal for recursive children below this level (defaults to crystal) */
  sub_crystal?: BaseChatModel;
  /** Maximum recursion depth. At depth >= max_depth, this gate returns null. */
  max_depth?: number;
  /** Current depth (0 = top-level). Framework manages this internally. */
  depth?: number;
  /** Shared usage tracker */
  usage?: UsageTracker;
  /** Parent context — used as fallback when the child is called without explicit context. */
  parent_context?: unknown;
  /** Progress callback for sub-agent activity. */
  onProgress?: RlmProgressCallback;
  /** Optional browser context to propagate to child agents. */
  browserContext?: BrowserContext;
  /** Parent's loom — when provided, child entities record into it (unified tree). */
  loom?: Loom;
  /** Returns the parent entity's most recent turn ID. Used as parent_turn_id for children. */
  getCurrentTurnId?: () => string | null;
};

/**
 * Gate factory: call_entity({ crystal, max_depth }) → BoundGate | null
 *
 * When invoked, spawns a child entity with an independent circle.
 * The child blocks the parent until it completes (COMP-2).
 * Child failure returns as an error string, doesn't kill the parent (COMP-8).
 * At depth >= max_depth, this gate returns null and should be excluded from the circle (COMP-6).
 */
export function call_entity(opts: CallEntityGateOptions): BoundGate | null {
  const {
    crystal,
    sub_crystal = crystal,
    max_depth = 2,
    depth = 0,
    usage,
    parent_context,
    onProgress,
    browserContext,
    loom,
    getCurrentTurnId,
  } = opts;

  // COMP-6: At depth >= max_depth, remove call_entity from the circle
  if (depth >= max_depth) {
    return null;
  }

  const docs: GateDocs = {
    sandbox_name: "llm_query",
    signature: "llm_query(query: string, subContext?: any): Promise<string>",
    description:
      "Delegate a subtask to a child language model. The child gets independent context and returns a string result. Use for breaking large tasks into smaller pieces or for recursive analysis.",
    examples: [
      'const answer = await llm_query("Summarize this section", data.slice(0, 1000))',
      'const result = await llm_query("What patterns do you see?", filtered_items)',
    ],
    section: "HOST FUNCTIONS",
  };

  return {
    name: "call_entity",
    definition: {
      name: "call_entity",
      description:
        "Spawn a child entity to handle a subtask. The child gets independent context and blocks until completion.",
      parameters: {
        type: "object",
        properties: {
          query: {
            type: "string",
            description: "The task/query for the child entity",
          },
          context: {
            type: "string",
            description:
              "Optional context data to pass to the child (JSON string)",
          },
        },
        required: ["query"],
        additionalProperties: false,
      },
    },
    ephemeral: false,
    docs,
    execute: async (args) => {
      const query = args.query as string;
      const rawContext = args.context;
      let childContext: unknown = undefined;

      if (rawContext !== undefined) {
        // Context may arrive as a string (JSON from tool-calling) or as an object
        // (direct value from sandbox positional arg mapping)
        if (typeof rawContext === "string") {
          try {
            childContext = JSON.parse(rawContext);
          } catch {
            childContext = rawContext;
          }
        } else {
          childContext = rawContext;
        }
      }

      // Fall back to parent_context when no explicit context is provided
      const contextToPass = childContext ?? parent_context ?? "No context provided";
      const childDepth = depth + 1;

      if (onProgress) {
        onProgress({ type: "sub_entity_start", depth: childDepth, query });
      }

      try {
        const { createRlmAgent } = await import("../../recipe/rlm");

        const parentTurnId = getCurrentTurnId?.() ?? undefined;
        const child = await createRlmAgent({
          llm: sub_crystal,
          subLlm: sub_crystal,
          context: contextToPass,
          maxDepth: max_depth,
          depth: childDepth,
          usage,
          onProgress,
          browserContext,
          loom,
          parent_turn_id: parentTurnId,
        });

        try {
          const result = await child.entity.cast(query);
          return result;
        } finally {
          child.sandbox.dispose();
          if (onProgress) {
            onProgress({ type: "sub_entity_end", depth: childDepth });
          }
        }
      } catch (err: any) {
        // COMP-8: Child failure returns as gate result, doesn't kill parent
        return `Error from child entity: ${err?.message ?? String(err)}`;
      }
    },
  };
}

const MAX_BATCH_CONCURRENCY = 8;
const MAX_BATCH_SIZE = 50;

/**
 * Gate factory: call_entity_batch({ crystal, max_depth }) → BoundGate | null
 *
 * Parallel delegation to multiple sub-entities. Processes tasks in chunks
 * with concurrency control. At depth >= max_depth, returns null.
 */
export function call_entity_batch(opts: CallEntityGateOptions): BoundGate | null {
  const {
    crystal,
    sub_crystal = crystal,
    max_depth = 2,
    depth = 0,
    usage,
    parent_context,
    onProgress,
    browserContext,
    loom,
    getCurrentTurnId,
  } = opts;

  // Same depth check as call_entity — at max depth, no batch either
  if (depth >= max_depth) {
    return null;
  }

  const docs: GateDocs = {
    sandbox_name: "llm_batch",
    signature: "llm_batch(tasks)",
    description:
      "Parallel delegation. Takes an array of `{query, context}` objects (max 50). Returns an array of strings.",
    examples: [
      'var tasks = items.map(function(item) { return { query: "Classify this.", context: item }; });\nvar results = llm_batch(tasks);',
    ],
    section: "HOST FUNCTIONS",
  };

  return {
    name: "call_entity_batch",
    definition: {
      name: "call_entity_batch",
      description:
        "Parallel delegation to multiple sub-entities. Returns an array of result strings.",
      parameters: {
        type: "object",
        properties: {
          tasks: {
            type: "array",
            items: {
              type: "object",
              properties: {
                query: { type: "string" },
                context: { type: "string" },
              },
              required: ["query"],
            },
            description: "Array of {query, context?} objects (max 50)",
          },
        },
        required: ["tasks"],
        additionalProperties: false,
      },
    },
    ephemeral: false,
    docs,
    execute: async (args) => {
      const tasks = args.tasks;

      if (!Array.isArray(tasks)) {
        throw new Error("llm_batch(tasks) requires an array of task objects.");
      }

      if (tasks.length > MAX_BATCH_SIZE) {
        throw new Error(
          `llm_batch: array too large (${tasks.length} > ${MAX_BATCH_SIZE}). Split into smaller batches.`,
        );
      }

      const childDepth = depth + 1;

      if (onProgress) {
        onProgress({ type: "batch_start", depth: childDepth, count: tasks.length });
      }

      const { createRlmAgent } = await import("../../recipe/rlm");

      const results: string[] = [];
      for (let i = 0; i < tasks.length; i += MAX_BATCH_CONCURRENCY) {
        const chunk = tasks.slice(i, i + MAX_BATCH_CONCURRENCY);
        const chunkResults = await Promise.all(
          chunk.map(async (task: any, j: number) => {
            const idx = i + j;
            const q =
              typeof task === "string"
                ? task
                : task != null
                  ? (task.query ?? task.input)
                  : undefined;
            if (typeof q !== "string") {
              throw new Error(
                `llm_batch: task[${idx}].query must be a string, got ${typeof q}`,
              );
            }
            const taskContext =
              typeof task === "object"
                ? (task.context ?? task.subContext)
                : undefined;
            const contextToPass = taskContext ?? parent_context ?? "No context provided";

            if (onProgress) {
              onProgress({
                type: "batch_item",
                depth: childDepth,
                index: idx,
                total: tasks.length,
                query: q,
              });
            }

            try {
              const parentTurnId = getCurrentTurnId?.() ?? undefined;
              const child = await createRlmAgent({
                llm: sub_crystal,
                subLlm: sub_crystal,
                context: contextToPass,
                maxDepth: max_depth,
                depth: childDepth,
                usage,
                onProgress,
                browserContext,
                loom,
                parent_turn_id: parentTurnId,
              });

              try {
                return await child.entity.cast(q);
              } finally {
                child.sandbox.dispose();
              }
            } catch (err: any) {
              return `Error from child entity: ${err?.message ?? String(err)}`;
            }
          }),
        );
        results.push(...chunkResults);
      }

      if (onProgress) {
        onProgress({ type: "batch_end", depth: childDepth });
      }

      // Return as array — the JS medium passes this directly to the sandbox.
      // In tool-calling mode this would be JSON-serialized by the framework.
      return results as any;
    },
  };
}
