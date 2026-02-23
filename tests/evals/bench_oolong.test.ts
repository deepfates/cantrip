/**
 * Benchmark: OOLONG-style Semantic Classification
 *
 * Faithful to the OOLONG trec_coarse benchmark:
 * entries are questions with IMPLICIT semantic categories.
 * The model must READ each question to classify it — context.filter() can't solve this.
 *
 * Uses OOLONG continuous scoring: score = 0.75^|y - ŷ|
 * Supports multi-run (NUM_RUNS) with fixed seed to measure approach variance.
 * Runs all evals in parallel (concurrency-limited) for speed.
 *
 * Requires OPENAI_API_KEY in .env (skips gracefully if missing).
 */
import { describe, test, expect } from "bun:test";
import { ChatOpenAI } from "../../src/crystal/providers/openai/chat";
import { generateOolongDataset } from "./generators";
import {
  runJsSandboxEval,
  runInContextEval,
  checkAnswerOolong,
  printMultiRunTable,
  runWithConcurrency,
  type EvalResult,
} from "./harness";
import { loadEnv } from "../helpers/env";

loadEnv();

const hasKey =
  Boolean(process.env.OPENAI_API_KEY) && Boolean(process.env.RUN_EVALS);
const modelName = process.env.OPENAI_MODEL ?? "gpt-5-mini";

// Entry counts: 50 (~4K chars), 200 (~16K), 500 (~40K), 1000 (~80K)
const SCALES = [50, 200, 500, 1000];

// Number of runs per (approach, scale) pair for statistical significance
const NUM_RUNS = parseInt(process.env.OOLONG_RUNS ?? "3", 10);

// depth=1 is very slow (spawns sub-LLMs per chunk), only run at small scales
const DEPTH1_MAX = 200;

// How many evals to run concurrently (limited by API rate limits)
const CONCURRENCY = parseInt(process.env.OOLONG_CONCURRENCY ?? "4", 10);

type EvalTask = {
  label: string;
  run: () => Promise<EvalResult>;
  entryCount: number;
  expected: string;
  targetLabel: string;
};

describe("OOLONG Semantic Classification (real LLM)", () => {
  (hasKey ? test : test.skip)(
    "Multi-run parallel evaluation",
    async () => {
      // Build all eval tasks upfront
      const tasks: EvalTask[] = [];

      for (const entryCount of SCALES) {
        const dataset = generateOolongDataset(entryCount);
        const { context, query, expected, targetLabel } = dataset;

        for (let run = 0; run < NUM_RUNS; run++) {
          const tag = NUM_RUNS > 1 ? ` [${run + 1}/${NUM_RUNS}]` : "";

          // JS-sandbox depth=0
          tasks.push({
            label: `JS-sandbox(d=0) @ ${entryCount}${tag}`,
            entryCount,
            expected,
            targetLabel,
            run: () =>
              runJsSandboxEval({
                llm: new ChatOpenAI({ model: modelName, temperature: 0 }),
                task: `oolong-d0-${entryCount}`,
                query,
                expected,
                context,
                maxDepth: 0,
                approach: "js-sandbox-d0",
              }),
          });

          // JS-sandbox depth=1 (small scales only)
          if (entryCount <= DEPTH1_MAX) {
            tasks.push({
              label: `JS-sandbox(d=1) @ ${entryCount}${tag}`,
              entryCount,
              expected,
              targetLabel,
              run: () =>
                runJsSandboxEval({
                  llm: new ChatOpenAI({ model: modelName, temperature: 0 }),
                  task: `oolong-d1-${entryCount}`,
                  query,
                  expected,
                  context,
                  maxDepth: 1,
                  approach: "js-sandbox-d1",
                }),
            });
          }

          // In-context
          tasks.push({
            label: `In-context @ ${entryCount}${tag}`,
            entryCount,
            expected,
            targetLabel,
            run: () =>
              runInContextEval({
                llm: new ChatOpenAI({ model: modelName, temperature: 0 }),
                task: `oolong-${entryCount}`,
                query,
                expected,
                context,
              }),
          });
        }
      }

      console.log(
        `Running ${tasks.length} evals with concurrency=${CONCURRENCY}...`,
      );

      // Run all evals in parallel with concurrency limit
      const results = await runWithConcurrency(
        tasks.map((t) => async () => {
          const result = await t.run();
          result.accuracy = checkAnswerOolong(result.answer, t.expected);
          console.log(
            `  ${t.label}: score=${result.accuracy.toFixed(3)} answer="${result.answer.slice(0, 30)}" expected=${t.expected} (${t.targetLabel}) total=${result.metrics.total_tokens}`,
          );
          return result;
        }),
        CONCURRENCY,
      );

      // Print results
      expect(results.length).toBe(tasks.length);
      printMultiRunTable(results);

      console.log("\nOOLONG Scores by approach (0.75^|error|):");
      const approaches = [...new Set(results.map((r) => r.approach))];
      for (const approach of approaches) {
        const approachResults = results.filter((r) => r.approach === approach);
        const avgScore =
          approachResults.reduce((s, r) => s + r.accuracy, 0) /
          approachResults.length;
        const scores = approachResults.map((r) => r.accuracy);
        const variance =
          scores.length > 1
            ? Math.sqrt(
                scores.reduce((s, v) => s + (v - avgScore) ** 2, 0) /
                  (scores.length - 1),
              )
            : 0;
        console.log(
          `  ${approach}: mean=${avgScore.toFixed(3)} std=${variance.toFixed(3)} (n=${approachResults.length})`,
        );
      }

      // Sanity: JS-sandbox-d0 should achieve non-trivial accuracy on average
      // (lenient threshold since OOLONG is the most variable benchmark)
      const sandboxD0Results = results.filter((r) => r.approach === "js-sandbox-d0");
      if (sandboxD0Results.length > 0) {
        const sandboxD0Avg =
          sandboxD0Results.reduce((s, r) => s + r.accuracy, 0) /
          sandboxD0Results.length;
        expect(sandboxD0Avg).toBeGreaterThan(0.3);
      }
    },
    // Total timeout: generous but bounded
    600_000,
  );
});
