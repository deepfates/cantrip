import type { BoundGate, GateDocs } from "../gate";
import type { DependencyOverrides } from "../depends";
import type { ProgressCallback } from "../../../entity/progress";
import { Depends } from "../depends";
import { rawGate } from "../raw";

/**
 * SpawnFn: creates a child entity, runs it on a query, returns the result string.
 * The spawn function is provided by the Entity at runtime via dependency_overrides.
 */
export type SpawnFn = (query: string, context: unknown) => Promise<string>;

/**
 * Framework-owned Depends instances.
 * The Entity auto-populates these via dependency_overrides at construction time.
 */
export const currentTurnIdBinding = new Depends<() => string | null>(
  () => { throw new Error("currentTurnId binding must be provided by entity"); },
);

export const spawnBinding = new Depends<SpawnFn>(
  () => { throw new Error("spawn binding must be provided by entity"); },
);

export const progressBinding = new Depends<ProgressCallback | null>(
  () => null,
);

export const depthBinding = new Depends<number>(
  () => 0,
);

export type CallEntityGateOptions = {
  /** Maximum recursion depth. At depth >= max_depth, this gate returns null. */
  max_depth?: number;
  /** Current depth (0 = top-level). Framework manages this internally. */
  depth?: number;
  /** Parent context — used as fallback when the child is called without explicit context. */
  parent_context?: unknown;
  /** Progress callback for sub-agent activity. */
  onProgress?: ProgressCallback;
};

/**
 * Gate factory: call_entity({ max_depth }) → BoundGate | null
 *
 * When invoked, spawns a child entity with an independent circle.
 * The child blocks the parent until it completes (COMP-2).
 * Child failure returns as an error string, doesn't kill the parent (COMP-8).
 * At depth >= max_depth, this gate returns null and should be excluded from the circle (COMP-6).
 *
 * Dynamic state (getCurrentTurnId, spawn function) is provided via Depends bindings,
 * populated by the Entity at construction time through dependency_overrides.
 */
export function call_entity(opts: CallEntityGateOptions = {}): BoundGate | null {
  const {
    max_depth = 2,
    depth = 0,
    parent_context,
    onProgress,
  } = opts;

  // COMP-6: At depth >= max_depth, remove call_entity from the circle
  if (depth >= max_depth) {
    return null;
  }

  const docs: GateDocs = {
    sandbox_name: "call_entity",
    signature: "call_entity(intent: string, subContext?: any): string",
    description:
      "Delegate a sub-intent to a child entity. The child gets independent context and returns a string result. Use for breaking large intents into smaller pieces or for recursive analysis.",
    examples: [
      'var answer = call_entity("Summarize this section", data.slice(0, 1000))',
      'var result = call_entity("What patterns do you see?", filtered_items)',
    ],
    section: "HOST FUNCTIONS",
  };

  const childDepth = depth + 1;

  const gate = rawGate(
    {
      name: "call_entity",
      description:
        "Spawn a child entity to handle a subtask. The child gets independent context and blocks until completion.",
      parameters: {
        type: "object",
        properties: {
          intent: {
            type: "string",
            description: "The sub-intent for the child entity",
          },
          context: {
            type: "string",
            description:
              "Optional context data to pass to the child (JSON string)",
          },
        },
        required: ["intent"],
        additionalProperties: false,
      },
    },
    async (args: Record<string, any>, deps: Record<string, any>) => {
      const query = (args.intent ?? args.query) as string;
      const rawContext = args.context;
      let childContext: unknown = undefined;

      if (rawContext !== undefined) {
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

      const progress: ProgressCallback | null = deps.onProgress;
      if (progress) {
        progress({ type: "sub_entity_start", depth: childDepth, query });
      }

      try {
        const spawn: SpawnFn = deps.spawn;
        const result = await spawn(query, contextToPass);
        return result;
      } catch (err: any) {
        // COMP-8: Child failure returns as gate result, doesn't kill parent
        return `Error from child entity: ${err?.message ?? String(err)}`;
      } finally {
        if (progress) {
          progress({ type: "sub_entity_end", depth: childDepth });
        }
      }
    },
    {
      dependencies: {
        spawn: spawnBinding,
        currentTurnId: currentTurnIdBinding,
        onProgress: progressBinding,
      },
    },
  );

  // Attach docs to the raw gate
  (gate as any).docs = docs;

  return gate;
}

const MAX_BATCH_CONCURRENCY = 8;
const MAX_BATCH_SIZE = 50;

/**
 * Gate factory: call_entity_batch({ max_depth }) → BoundGate | null
 *
 * Parallel delegation to multiple sub-entities. Processes tasks in chunks
 * with concurrency control. At depth >= max_depth, returns null.
 */
export function call_entity_batch(opts: CallEntityGateOptions = {}): BoundGate | null {
  const {
    max_depth = 2,
    depth = 0,
    parent_context,
    onProgress,
  } = opts;

  // Same depth check as call_entity — at max depth, no batch either
  if (depth >= max_depth) {
    return null;
  }

  const docs: GateDocs = {
    sandbox_name: "call_entity_batch",
    signature: "call_entity_batch(tasks)",
    description:
      "Parallel delegation. Takes an array of `{intent, context}` objects (max 50). Returns an array of strings.",
    examples: [
      'var tasks = items.map(function(item) { return { intent: "Classify this.", context: item }; });\nvar results = call_entity_batch(tasks);',
    ],
    section: "HOST FUNCTIONS",
  };

  const childDepth = depth + 1;

  // Hand-built BoundGate (not rawGate) because the batch returns a raw array
  // that must pass through to the sandbox without serializeBoundGate wrapping.
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
                intent: { type: "string" },
                context: { type: "string" },
              },
              required: ["intent"],
            },
            description: "Array of {intent, context?} objects (max 50)",
          },
        },
        required: ["tasks"],
        additionalProperties: false,
      },
    },
    ephemeral: false,
    docs,
    execute: async (args: Record<string, any>, overrides?: DependencyOverrides) => {
      // Resolve dependencies via Depends
      const spawn: SpawnFn = await spawnBinding.resolve(overrides);
      const progress: ProgressCallback | null = await progressBinding.resolve(overrides);

      const tasks = args.tasks;

      if (!Array.isArray(tasks)) {
        throw new Error("call_entity_batch(tasks) requires an array of task objects.");
      }

      if (tasks.length > MAX_BATCH_SIZE) {
        throw new Error(
          `call_entity_batch: array too large (${tasks.length} > ${MAX_BATCH_SIZE}). Split into smaller batches.`,
        );
      }

      if (progress) {
        progress({ type: "batch_start", depth: childDepth, count: tasks.length });
      }

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
                  ? (task.intent ?? task.query ?? task.input)
                  : undefined;
            if (typeof q !== "string") {
              throw new Error(
                `call_entity_batch: task[${idx}].intent must be a string, got ${typeof q}`,
              );
            }
            const taskContext =
              typeof task === "object"
                ? (task.context ?? task.subContext)
                : undefined;
            const contextToPass = taskContext ?? parent_context ?? "No context provided";

            if (progress) {
              progress({
                type: "batch_item",
                depth: childDepth,
                index: idx,
                total: tasks.length,
                query: q,
              });
            }

            try {
              return await spawn(q, contextToPass);
            } catch (err: any) {
              return `Error from child entity: ${err?.message ?? String(err)}`;
            }
          }),
        );
        results.push(...chunkResults);
      }

      if (progress) {
        progress({ type: "batch_end", depth: childDepth });
      }

      // Return as array — the JS medium passes this directly to the sandbox.
      // In tool-calling mode this would be JSON-serialized by the framework.
      return results as any;
    },
  };
}
