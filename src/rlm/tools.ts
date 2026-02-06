import { tool } from "../tools/decorator";
import { z } from "zod";
import { JsAsyncContext } from "../tools/builtin/js_async_context";
import { TaskComplete } from "../agent/errors";
import { Depends } from "../tools/depends";

/**
 * Formats sandbox execution results into a compact metadata string.
 * This prevents the Agent's prompt history from being flooded with large data dumps.
 */
function formatRlmMetadata(output: string): string {
  if (!output || output === "undefined") return "[Result: undefined]";
  const length = output.length;
  const preview = output.slice(0, 150).replace(/\n/g, " ");
  return `[Result: ${length} chars] "${preview}${length > 150 ? "..." : ""}"`;
}

/**
 * Dependency key for injecting the RLM sandbox into the tool execution context.
 */
export const getRlmSandbox = new Depends<JsAsyncContext>(
  function getRlmSandbox() {
    throw new Error("RlmSandbox not provided");
  },
);

/**
 * The core 'js' tool for Recursive Language Models.
 * Executes JavaScript in the sandbox and returns only metadata to the LLM.
 */
export const js_rlm = tool(
  "Execute JavaScript in the persistent sandbox. Results are returned as metadata. You MUST use submit_answer() to return your final result.",
  async ({ code, timeout_ms }: { code: string; timeout_ms?: number }, deps) => {
    const sandbox = deps.sandbox as JsAsyncContext;

    try {
      const result = await sandbox.evalCode(code, {
        executionTimeoutMs: timeout_ms,
      });

      if (!result.ok) {
        // Handle the internal bridge signal for termination
        if (result.error.startsWith("SIGNAL_FINAL:")) {
          throw new TaskComplete(result.error.replace("SIGNAL_FINAL:", ""));
        }

        let error = result.error;
        // Provide clear guidance on sandbox physics (Asyncify limitations)
        if (error.includes("Lifetime not alive")) {
          error +=
            " (Note: All sandbox functions are blocking. Do NOT use async/await, async functions, or Promises.)";
        }
        return `Error: ${error}`;
      }

      return formatRlmMetadata(result.output);
    } catch (e: any) {
      if (e instanceof TaskComplete) throw e;

      let msg = String(e?.message ?? e);
      if (msg.includes("Lifetime not alive")) {
        msg +=
          " (Note: All sandbox functions are blocking. Do NOT use async/await, async functions, or Promises.)";
      }
      return `Error: ${msg}`;
    }
  },
  {
    name: "js",
    zodSchema: z.object({
      code: z.string().describe("JavaScript code to execute."),
      timeout_ms: z.number().int().positive().optional(),
    }),
    dependencies: { sandbox: getRlmSandbox },
  },
);

/**
 * Bridges the JS Sandbox to the Host by registering RLM primitives.
 */
export async function registerRlmFunctions(options: {
  sandbox: JsAsyncContext;
  context: unknown;
  onLlmQuery: (query: string, subContext?: unknown) => Promise<string>;
}) {
  const { sandbox, context, onLlmQuery } = options;

  // 1. Inject the data context as a global variable.
  sandbox.setGlobal("context", context);

  // 2. submit_answer: The canonical way to return a result to the user.
  sandbox.registerAsyncFunction("submit_answer", async (value) => {
    const result =
      typeof value === "string" ? value : JSON.stringify(value, null, 2);
    throw new Error(`SIGNAL_FINAL:${result}`);
  });

  // 3. llm_query: Recursive delegation to a sub-agent.
  sandbox.registerAsyncFunction("llm_query", async (query, subContext) => {
    let q = query;
    let c = subContext;

    // Robustness: handle case where LLM passes an object { query, context } or { input }
    if (typeof query === "object" && query !== null) {
      q = (query as any).query ?? (query as any).input ?? (query as any).task;
      c = c ?? (query as any).context ?? (query as any).subContext;
    }

    if (typeof q !== "string") {
      throw new Error("llm_query(query, context) requires a string query.");
    }

    // Log to stderr so user sees progress (stdout is captured for LLM)
    const contextSize = c ? JSON.stringify(c).length : 0;
    console.error(
      `[llm_query] "${q.slice(0, 60)}${q.length > 60 ? "..." : ""}" (${contextSize} chars)`,
    );

    const result = await onLlmQuery(q, c);

    console.error(`[llm_query] done`);
    return result;
  });

  // 4. llm_batch: Parallel delegation for processing multiple snippets.
  // Limit concurrency to avoid resource exhaustion from LLM-controlled input
  const MAX_BATCH_CONCURRENCY = 8;

  sandbox.registerAsyncFunction("llm_batch", async (tasks) => {
    if (!Array.isArray(tasks)) {
      throw new Error("llm_batch(tasks) requires an array of task objects.");
    }

    // Cap array size to prevent DoS
    const MAX_BATCH_SIZE = 50;
    if (tasks.length > MAX_BATCH_SIZE) {
      throw new Error(
        `llm_batch: array too large (${tasks.length} > ${MAX_BATCH_SIZE}). Split into smaller batches.`,
      );
    }

    console.error(
      `[llm_batch] spawning ${tasks.length} sub-agents (max ${MAX_BATCH_CONCURRENCY} concurrent)...`,
    );

    // Process in chunks to limit concurrency
    const results: string[] = [];
    for (let i = 0; i < tasks.length; i += MAX_BATCH_CONCURRENCY) {
      const chunk = tasks.slice(i, i + MAX_BATCH_CONCURRENCY);
      const chunkResults = await Promise.all(
        chunk.map(async (task: any, j: number) => {
          const idx = i + j;
          const q =
            typeof task === "string" ? task : (task.query ?? task.input);
          const c =
            typeof task === "object"
              ? (task.context ?? task.subContext)
              : undefined;
          const result = await onLlmQuery(q, c);
          console.error(`[llm_batch] ${idx + 1}/${tasks.length} complete`);
          return result;
        }),
      );
      results.push(...chunkResults);
    }

    console.error(`[llm_batch] all ${tasks.length} done`);
    return results;
  });
}
