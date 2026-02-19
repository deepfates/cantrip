/**
 * Evaluation harness for real LLM benchmarks.
 *
 * Runs the same task against RLM and Entity+JS baselines with real LLMs,
 * collecting actual token usage from the API.
 *
 * Addresses fairness concerns from code review:
 * - Three baselines: RLM, Entity+JS (full output), Entity+JS (metadata-only)
 * - Prompt parity: Entity baselines get equivalent prompt quality to RLM
 * - Both use require_done_tool: true for symmetric termination
 * - Context preview provided to all approaches
 * - Cached tokens tracked separately
 */
import { Entity } from "../../src/cantrip/entity";
import { Circle } from "../../src/circle/circle";
import { analyzeContext, createRlmAgent } from "../../src/circle/recipe/rlm";
import { JsContext, getJsContext } from "../../src/circle/medium/js/context";
import { done } from "../../src/circle/gate/builtin/done";
import { gate } from "../../src/circle/gate/decorator";
import { z } from "zod";
import { UsageTracker } from "../../src/crystal/tokens/usage";
import type { BaseChatModel } from "../../src/crystal/crystal";

// --- Local JS gate for eval baselines (full output) ---

const DEFAULT_MAX_OUTPUT_CHARS = 9500;

function truncateOutput(output: string, maxChars: number): string {
  if (output.length <= maxChars) return output;
  const lastNewline = output.lastIndexOf("\n", maxChars);
  const cutoff = lastNewline > maxChars / 2 ? lastNewline : maxChars;
  return output.substring(0, cutoff) + `\n\n... [output truncated at ${maxChars} chars]`;
}

const js = gate(
  "Execute JavaScript in a persistent, isolated sandbox. State persists across calls.",
  async (
    { code, timeout_ms, max_output_chars }: { code: string; timeout_ms?: number; max_output_chars?: number },
    deps,
  ) => {
    const ctx = deps.ctx as JsContext;
    const maxChars = max_output_chars ?? DEFAULT_MAX_OUTPUT_CHARS;
    try {
      const result = await ctx.evalCode(code, { executionTimeoutMs: timeout_ms });
      if (!result.ok) return truncateOutput(`Error: ${result.error}`, maxChars);
      return truncateOutput(result.output, maxChars);
    } catch (e: any) {
      return truncateOutput(`Error: ${String(e?.message ?? e)}`, maxChars);
    }
  },
  {
    name: "js",
    zodSchema: z.object({
      code: z.string().describe("The Javascript code to execute in the sandbox."),
      timeout_ms: z.number().int().positive().optional(),
      max_output_chars: z.number().int().positive().optional(),
    }),
    dependencies: { ctx: getJsContext },
  },
);

// --- Result Types ---

export type InvocationMetric = {
  prompt_tokens: number;
  completion_tokens: number;
  cached_tokens: number;
};

export type EvalMetrics = {
  total_tokens: number;
  total_prompt_tokens: number;
  total_completion_tokens: number;
  total_cached_tokens: number;
  /** total_prompt_tokens - total_cached_tokens + total_completion_tokens */
  billable_tokens: number;
  num_invocations: number;
  max_single_prompt: number;
  per_invocation: InvocationMetric[];
};

export type EvalResult = {
  approach: string;
  task: string;
  context_size: number;
  accuracy: number;
  answer: string;
  expected: string;
  metrics: EvalMetrics;
  duration_ms: number;
};

// --- Metric Extraction ---

export function extractMetrics(tracker: UsageTracker): EvalMetrics {
  const history = tracker.getHistory();
  const per_invocation: InvocationMetric[] = history.map((entry) => ({
    prompt_tokens: entry.usage.prompt_tokens,
    completion_tokens: entry.usage.completion_tokens,
    cached_tokens: entry.usage.prompt_cached_tokens ?? 0,
  }));

  const total_prompt_tokens = history.reduce(
    (sum, e) => sum + e.usage.prompt_tokens,
    0,
  );
  const total_completion_tokens = history.reduce(
    (sum, e) => sum + e.usage.completion_tokens,
    0,
  );
  const total_cached_tokens = history.reduce(
    (sum, e) => sum + (e.usage.prompt_cached_tokens ?? 0),
    0,
  );
  const max_single_prompt = history.reduce(
    (max, e) => Math.max(max, e.usage.prompt_tokens),
    0,
  );

  return {
    total_tokens: total_prompt_tokens + total_completion_tokens,
    total_prompt_tokens,
    total_completion_tokens,
    total_cached_tokens,
    billable_tokens:
      total_prompt_tokens - total_cached_tokens + total_completion_tokens,
    num_invocations: history.length,
    max_single_prompt,
    per_invocation,
  };
}

// --- Metadata-only JS tool (fair comparison variant) ---

function formatMetadata(output: string): string {
  if (!output || output === "undefined") return "[Result: undefined]";
  const length = output.length;
  const preview = output.slice(0, 150).replace(/\n/g, " ");
  return `[Result: ${length} chars] "${preview}${length > 150 ? "..." : ""}"`;
}

/**
 * JS tool that returns metadata-only output, identical to RLM's js_rlm tool
 * but using the standard sync JsContext (not async). This isolates the
 * metadata-vs-full-output variable from the sandbox implementation.
 */
const js_meta = gate(
  "Execute JavaScript in the persistent sandbox. Results are returned as metadata summaries, not full output. Use console.log() to inspect values.",
  async ({ code, timeout_ms }: { code: string; timeout_ms?: number }, deps) => {
    const ctx = deps.ctx as JsContext;
    try {
      const result = await ctx.evalCode(code, {
        executionTimeoutMs: timeout_ms,
      });
      if (!result.ok) return `Error: ${result.error}`;
      return formatMetadata(result.output);
    } catch (e: any) {
      return `Error: ${String(e?.message ?? e)}`;
    }
  },
  {
    name: "js",
    zodSchema: z.object({
      code: z.string().describe("JavaScript code to execute."),
      timeout_ms: z.number().int().positive().optional(),
    }),
    dependencies: { ctx: getJsContext },
  },
);

// --- Entity System Prompt (parity with RLM prompt) ---

function getEntitySystemPrompt(
  meta: { type: string; length: number; preview: string },
  metadataOnly: boolean,
): string {
  const outputNote = metadataOnly
    ? `Results from the js tool are returned as **metadata summaries** (length + 150 char preview), not full output. You will only see truncated outputs, so use console.log() strategically to inspect specific values.`
    : `Results from the js tool are returned as **full output** (truncated at 9500 chars).`;

  return `You are tasked with answering a query about data that has been pre-loaded into a persistent JavaScript sandbox. You can access, transform, and analyze this data interactively. You will be queried iteratively until you provide a final answer.

### DATA ENVIRONMENT
A global variable \`context\` contains the full dataset:
- **Type**: ${meta.type}
- **Length**: ${meta.length} characters
- **Preview**: "${meta.preview.replace(/\n/g, " ")}..."

You MUST use the \`js\` tool to explore this variable. You cannot see the data otherwise.
Make sure you look through the context sufficiently before answering your query.
${outputNote}

### SANDBOX PHYSICS
1. The \`js\` tool executes JavaScript in a persistent sandbox. Variables persist between calls.
2. Use \`var\` or \`globalThis\` to save state between \`js\` tool calls.
3. Call the \`done\` tool with your final answer. This is the ONLY way to finish.

### STRATEGY
First probe the context to understand its structure and size. Then choose the right approach:
- **Code-solvable tasks** (counting, filtering, searching, regex): Use JavaScript directly. This is fast and exact.
- **Semantic/comprehension tasks**: You may need multiple rounds of exploration and careful analysis.
- **Large datasets**: Process systematically — don't try to inspect everything at once.

Analyze your input data before choosing a strategy. For structured data, code is usually sufficient.

### EXAMPLE: Code-solvable task (filtering/counting)
\`\`\`javascript
// Probe the context
console.log("Type:", typeof context, "Length:", Array.isArray(context) ? context.length : context.length);
console.log("Sample:", JSON.stringify(Array.isArray(context) ? context[0] : context.slice(0, 300)));

// Filter and count
var count = context.filter(function(item) { return item.age > 30; }).length;
console.log("Count:", count);
\`\`\`

### EXAMPLE: Search task (finding a value in text)
\`\`\`javascript
console.log("Length:", context.length);
console.log("First 500 chars:", context.slice(0, 500));

var match = context.match(/SECRET_CODE:\\s*"([^"]+)"/);
if (match) {
  console.log("Found:", match[1]);
} else {
  // Try searching in chunks
  var chunkSize = 10000;
  for (var i = 0; i < context.length; i += chunkSize) {
    var chunk = context.slice(i, i + chunkSize + 100);
    var m = chunk.match(/SECRET_CODE:\\s*"([^"]+)"/);
    if (m) { console.log("Found:", m[1]); break; }
  }
}
\`\`\`

### EXAMPLE: Multi-step reasoning
\`\`\`javascript
// Step 1: Find relevant entries
var matches = context.filter(function(doc) { return doc.city === "Atlantis"; });
console.log("Matches:", JSON.stringify(matches));

// Step 2: Extract the answer from matched entries
var name = matches[0].name;
var colorEntry = context.find(function(doc) { return doc.name === name && doc.favoriteColor; });
console.log("Color:", colorEntry ? colorEntry.favoriteColor : "not found");
\`\`\`

Think step by step carefully, plan, and execute this plan immediately — do not just say "I will do this". Use the sandbox to explore and process the data. Remember to explicitly answer the original query via the \`done\` tool.
`;
}

// --- Eval Runners ---

/**
 * Run a task using the RLM approach.
 * Context lives in the async sandbox; LLM only sees metadata.
 */
export async function runRlmEval(options: {
  llm: BaseChatModel;
  task: string;
  query: string;
  expected: string;
  context: unknown;
  maxDepth?: number;
  approach?: string;
}): Promise<EvalResult> {
  const {
    llm,
    task,
    query,
    expected,
    context,
    maxDepth = 1,
    approach = "rlm",
  } = options;
  const usage = new UsageTracker();
  const contextStr =
    typeof context === "string" ? context : JSON.stringify(context);

  const start = Date.now();
  const { entity, sandbox } = await createRlmAgent({
    llm,
    context,
    usage,
    maxDepth,
  });

  let answer: string;
  const EVAL_TIMEOUT_MS = 240_000; // 4 minutes hard wall-clock limit
  try {
    answer = await Promise.race([
      entity.cast(query),
      new Promise<string>((_, reject) =>
        setTimeout(
          () => reject(new Error("RLM eval timeout")),
          EVAL_TIMEOUT_MS,
        ),
      ),
    ]);
  } catch (e: any) {
    answer = `[ERROR: ${e?.message ?? String(e)}]`;
  } finally {
    sandbox.dispose();
  }
  const duration_ms = Date.now() - start;

  const metrics = extractMetrics(usage);
  const accuracy = checkAnswer(answer, expected);

  return {
    approach,
    task,
    context_size: contextStr.length,
    accuracy,
    answer,
    expected,
    metrics,
    duration_ms,
  };
}

/**
 * Run a task using an Entity with the JS tool (full output).
 * Context is pre-loaded into a JsContext sandbox.
 * Uses prompt parity with RLM and require_done_tool for symmetric termination.
 */
export async function runEntityWithJsEval(options: {
  llm: BaseChatModel;
  task: string;
  query: string;
  expected: string;
  context: unknown;
}): Promise<EvalResult> {
  const { llm, task, query, expected, context } = options;
  const usage = new UsageTracker();
  const contextStr =
    typeof context === "string" ? context : JSON.stringify(context);

  const jsCtx = await JsContext.create({ executionTimeoutMs: 30000 });
  await injectContext(jsCtx, context);

  const overrides = new Map<any, any>();
  overrides.set(getJsContext, () => jsCtx);

  const meta = analyzeContext(context);
  const systemPrompt = getEntitySystemPrompt(meta, false);

  const start = Date.now();
  const circle = Circle({
    gates: [js, done],
    wards: [{ max_turns: 20, require_done_tool: true }],
  });
  const entity = new Entity({
    crystal: llm,
    call: {
      system_prompt: systemPrompt,
      hyperparameters: { tool_choice: "auto" },
      gate_definitions: [],
    },
    circle,
    dependency_overrides: overrides,
    usage_tracker: usage,
  });

  let answer: string;
  try {
    answer = await entity.cast(query);
  } finally {
    jsCtx.dispose();
  }
  const duration_ms = Date.now() - start;

  const metrics = extractMetrics(usage);
  const accuracy = checkAnswer(answer, expected);

  return {
    approach: "entity+js",
    task,
    context_size: contextStr.length,
    accuracy,
    answer,
    expected,
    metrics,
    duration_ms,
  };
}

/**
 * Run a task using an Entity with metadata-only JS tool output.
 * This is the fairest comparison to RLM: same metadata policy, same prompt,
 * but using the standard Entity loop (not RLM's sandbox/submit_answer).
 */
export async function runEntityMetaJsEval(options: {
  llm: BaseChatModel;
  task: string;
  query: string;
  expected: string;
  context: unknown;
}): Promise<EvalResult> {
  const { llm, task, query, expected, context } = options;
  const usage = new UsageTracker();
  const contextStr =
    typeof context === "string" ? context : JSON.stringify(context);

  const jsCtx = await JsContext.create({ executionTimeoutMs: 30000 });
  await injectContext(jsCtx, context);

  const overrides = new Map<any, any>();
  overrides.set(getJsContext, () => jsCtx);

  const meta = analyzeContext(context);
  const systemPrompt = getEntitySystemPrompt(meta, true);

  const start = Date.now();
  const circle = Circle({
    gates: [js_meta, done],
    wards: [{ max_turns: 20, require_done_tool: true }],
  });
  const entity = new Entity({
    crystal: llm,
    call: {
      system_prompt: systemPrompt,
      hyperparameters: { tool_choice: "auto" },
      gate_definitions: [],
    },
    circle,
    dependency_overrides: overrides,
    usage_tracker: usage,
  });

  let answer: string;
  try {
    answer = await entity.cast(query);
  } finally {
    jsCtx.dispose();
  }
  const duration_ms = Date.now() - start;

  const metrics = extractMetrics(usage);
  const accuracy = checkAnswer(answer, expected);

  return {
    approach: "entity+js-meta",
    task,
    context_size: contextStr.length,
    accuracy,
    answer,
    expected,
    metrics,
    duration_ms,
  };
}

/**
 * Run a task by stuffing the full context into the LLM prompt. No tools, no sandbox.
 * Single query() call — the simplest possible baseline.
 */
export async function runInContextEval(options: {
  llm: BaseChatModel;
  task: string;
  query: string;
  expected: string;
  context: unknown;
}): Promise<EvalResult> {
  const { llm, task, query, expected, context } = options;
  const usage = new UsageTracker();
  const contextStr =
    typeof context === "string" ? context : JSON.stringify(context);

  const start = Date.now();
  let answer: string;
  try {
    const res = await llm.query([
      {
        role: "user",
        content: `${query}\n\nHere is the full data:\n\n${contextStr}`,
      },
    ]);
    if (res.usage) {
      usage.add(llm.model, res.usage);
    }
    answer = res.content ?? "";
  } catch (e: any) {
    answer = `[ERROR: ${e?.message ?? String(e)}]`;
  }
  const duration_ms = Date.now() - start;

  const metrics = extractMetrics(usage);
  const accuracy = checkAnswer(answer, expected);

  return {
    approach: "in-context",
    task,
    context_size: contextStr.length,
    accuracy,
    answer,
    expected,
    metrics,
    duration_ms,
  };
}

// --- Helpers ---

async function injectContext(jsCtx: JsContext, context: unknown) {
  const jsonStr = JSON.stringify(context);
  await jsCtx.evalCode(`var context = JSON.parse(${JSON.stringify(jsonStr)});`);
}

function checkAnswer(answer: string, expected: string): number {
  const norm = (s: string) => s.toLowerCase().trim();
  const normAns = norm(answer);
  const normExp = norm(expected);

  // For numeric expected values, extract the number from the answer
  // and compare exactly (prevents "420" matching "42")
  if (/^\d+$/.test(normExp)) {
    const expNum = parseInt(normExp, 10);
    // Try to find the exact number in the answer
    const numbers = normAns.match(/\d+/g);
    if (numbers && numbers.some((n) => parseInt(n, 10) === expNum)) return 1;
    return 0;
  }

  // For non-numeric values, substring match is fine
  if (normAns.includes(normExp)) return 1;
  return 0;
}

/**
 * OOLONG-style continuous scoring for numeric answers.
 * score = 0.75^|y - ŷ|  (from the OOLONG paper)
 * Returns 1.0 for exact match, degrades smoothly with distance.
 */
export function checkAnswerOolong(answer: string, expected: string): number {
  // Extract first number from each string
  const ansNum = parseFloat(answer.replace(/[^0-9.-]/g, ""));
  const expNum = parseFloat(expected);
  if (isNaN(ansNum) || isNaN(expNum)) return 0;
  return Math.pow(0.75, Math.abs(ansNum - expNum));
}

// --- Multi-run Support ---

export type MultiRunResult = {
  approach: string;
  task: string;
  context_size: number;
  runs: EvalResult[];
  mean_accuracy: number;
  std_accuracy: number;
  mean_total_tokens: number;
  std_total_tokens: number;
  mean_billable_tokens: number;
  mean_prompt_tokens: number;
  mean_duration_ms: number;
};

function stddev(values: number[]): number {
  if (values.length < 2) return 0;
  const mean = values.reduce((a, b) => a + b, 0) / values.length;
  const variance =
    values.reduce((sum, v) => sum + (v - mean) ** 2, 0) / (values.length - 1);
  return Math.sqrt(variance);
}

export function aggregateRuns(results: EvalResult[]): MultiRunResult {
  const first = results[0];
  const accuracies = results.map((r) => r.accuracy);
  const totals = results.map((r) => r.metrics.total_tokens);
  const billables = results.map((r) => r.metrics.billable_tokens);
  const prompts = results.map((r) => r.metrics.total_prompt_tokens);
  const durations = results.map((r) => r.duration_ms);

  return {
    approach: first.approach,
    task: first.task,
    context_size: first.context_size,
    runs: results,
    mean_accuracy: accuracies.reduce((a, b) => a + b, 0) / accuracies.length,
    std_accuracy: stddev(accuracies),
    mean_total_tokens: totals.reduce((a, b) => a + b, 0) / totals.length,
    std_total_tokens: stddev(totals),
    mean_billable_tokens:
      billables.reduce((a, b) => a + b, 0) / billables.length,
    mean_prompt_tokens: prompts.reduce((a, b) => a + b, 0) / prompts.length,
    mean_duration_ms: durations.reduce((a, b) => a + b, 0) / durations.length,
  };
}

export function printMultiRunTable(allResults: EvalResult[]) {
  // Group by (context_size, approach)
  const groups = new Map<string, EvalResult[]>();
  for (const r of allResults) {
    const key = `${r.context_size}|${r.approach}`;
    const group = groups.get(key) ?? [];
    group.push(r);
    groups.set(key, group);
  }

  const aggregated = [...groups.values()].map(aggregateRuns);
  const bySize = new Map<number, MultiRunResult[]>();
  for (const a of aggregated) {
    const group = bySize.get(a.context_size) ?? [];
    group.push(a);
    bySize.set(a.context_size, group);
  }

  const sizes = [...bySize.keys()].sort((a, b) => a - b);
  const n = aggregated[0]?.runs.length ?? 1;

  const header = [
    "Size".padEnd(12),
    "Approach".padEnd(16),
    `Acc±std(n=${n})`.padEnd(14),
    "Prompt".padEnd(10),
    "Total±std".padEnd(16),
    "Billable".padEnd(10),
    "Time".padEnd(8),
  ].join(" | ");

  console.log("\n" + "=".repeat(header.length));
  console.log(header);
  console.log("-".repeat(header.length));

  for (const size of sizes) {
    const group = bySize.get(size)!;
    for (const a of group) {
      const accStr =
        a.std_accuracy > 0
          ? `${a.mean_accuracy.toFixed(2)}±${a.std_accuracy.toFixed(2)}`
          : a.mean_accuracy.toFixed(2);
      const row = [
        String(size).padEnd(12),
        a.approach.padEnd(16),
        accStr.padEnd(14),
        Math.round(a.mean_prompt_tokens).toString().padEnd(10),
        `${Math.round(a.mean_total_tokens)}±${Math.round(a.std_total_tokens)}`.padEnd(
          16,
        ),
        Math.round(a.mean_billable_tokens).toString().padEnd(10),
        `${(a.mean_duration_ms / 1000).toFixed(1)}s`.padEnd(8),
      ].join(" | ");
      console.log(row);
    }
    if (size !== sizes[sizes.length - 1])
      console.log("-".repeat(header.length));
  }
  console.log("=".repeat(header.length));
}

// --- Comparison & Reporting ---

export function printComparisonTable(results: EvalResult[]) {
  const bySize = new Map<number, EvalResult[]>();
  for (const r of results) {
    const group = bySize.get(r.context_size) ?? [];
    group.push(r);
    bySize.set(r.context_size, group);
  }

  const sizes = [...bySize.keys()].sort((a, b) => a - b);

  const header = [
    "Size".padEnd(12),
    "Approach".padEnd(16),
    "Acc".padEnd(5),
    "Prompt".padEnd(10),
    "Cached".padEnd(10),
    "Billable".padEnd(10),
    "Total".padEnd(10),
    "Calls".padEnd(7),
    "MaxPrm".padEnd(10),
    "Time".padEnd(8),
  ].join(" | ");

  console.log("\n" + "=".repeat(header.length));
  console.log(header);
  console.log("-".repeat(header.length));

  for (const size of sizes) {
    const group = bySize.get(size)!;
    for (const r of group) {
      const m = r.metrics;
      const row = [
        String(size).padEnd(12),
        r.approach.padEnd(16),
        r.accuracy.toFixed(1).padEnd(5),
        String(m.total_prompt_tokens).padEnd(10),
        String(m.total_cached_tokens).padEnd(10),
        String(m.billable_tokens).padEnd(10),
        String(m.total_tokens).padEnd(10),
        String(m.num_invocations).padEnd(7),
        String(m.max_single_prompt).padEnd(10),
        `${(r.duration_ms / 1000).toFixed(1)}s`.padEnd(8),
      ].join(" | ");
      console.log(row);
    }
    if (size !== sizes[sizes.length - 1])
      console.log("-".repeat(header.length));
  }

  console.log("=".repeat(header.length));

  // Scaling summary
  const approaches = [...new Set(results.map((r) => r.approach))];
  console.log("\nScaling Summary:");
  for (const approach of approaches) {
    const approachResults = results
      .filter((r) => r.approach === approach)
      .sort((a, b) => a.context_size - b.context_size);
    if (approachResults.length >= 2) {
      const first = approachResults[0];
      const last = approachResults[approachResults.length - 1];
      const sizeRatio = last.context_size / first.context_size;
      const promptRatio =
        last.metrics.total_prompt_tokens / first.metrics.total_prompt_tokens;
      const billableRatio =
        last.metrics.billable_tokens / first.metrics.billable_tokens;
      console.log(
        `  ${approach}: context ${sizeRatio.toFixed(0)}x → prompt ${promptRatio.toFixed(2)}x, billable ${billableRatio.toFixed(2)}x`,
      );
    }
  }

  // Per-invocation breakdown for largest scale
  const largestSize = sizes[sizes.length - 1];
  const largestGroup = bySize.get(largestSize)!;
  console.log(`\nPer-invocation breakdown (context size ${largestSize}):`);
  for (const r of largestGroup) {
    console.log(`  ${r.approach}:`);
    r.metrics.per_invocation.forEach((inv, i) => {
      console.log(
        `    call ${i + 1}: prompt=${inv.prompt_tokens} cached=${inv.cached_tokens} completion=${inv.completion_tokens}`,
      );
    });
  }
}

// --- Parallel Execution ---

/**
 * Run async tasks with a concurrency limit.
 * Each task is a function that returns a Promise<T>.
 */
export async function runWithConcurrency<T>(
  tasks: Array<() => Promise<T>>,
  concurrency: number,
): Promise<T[]> {
  const results: T[] = new Array(tasks.length);
  let nextIndex = 0;

  async function worker() {
    while (nextIndex < tasks.length) {
      const index = nextIndex++;
      results[index] = await tasks[index]();
    }
  }

  const workers = Array.from(
    { length: Math.min(concurrency, tasks.length) },
    () => worker(),
  );
  await Promise.all(workers);
  return results;
}
