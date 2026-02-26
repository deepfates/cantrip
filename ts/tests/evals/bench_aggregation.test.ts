/**
 * Benchmark: Aggregation (OOLONG style)
 *
 * Uses real LLMs to count/filter records across datasets of increasing size.
 * Three approaches compared:
<<<<<<< HEAD
 * - JS-sandbox: context in sandbox, metadata-only output
 * - Entity+JS: context in sandbox, full output to LLM
 * - Entity+JS-meta: context in sandbox, metadata-only output (fair control)
=======
 * - RLM: context in sandbox, metadata-only output
 * - Agent+JS: context in sandbox, full output to LLM
 * - Agent+JS-meta: context in sandbox, metadata-only output (fair control)
>>>>>>> monorepo/main
 *
 * Requires OPENAI_API_KEY in .env (skips gracefully if missing).
 */
import { describe, test, expect } from "bun:test";
<<<<<<< HEAD
import { ChatOpenAI } from "../../src/crystal/providers/openai/chat";
import { generatePersonRecords, computePersonAnswers } from "./generators";
import {
  runJsSandboxEval,
  runEntityWithJsEval,
  runEntityMetaJsEval,
=======
import { ChatOpenAI } from "../../src/llm/openai/chat";
import { generatePersonRecords, computePersonAnswers } from "./generators";
import {
  runRlmEval,
  runAgentWithJsEval,
  runAgentMetaJsEval,
>>>>>>> monorepo/main
  runInContextEval,
  printComparisonTable,
  type EvalResult,
} from "./harness";
import { loadEnv } from "../helpers/env";

loadEnv();

const hasKey =
  Boolean(process.env.OPENAI_API_KEY) && Boolean(process.env.RUN_EVALS);
const it = hasKey ? test : test.skip;
const modelName = process.env.OPENAI_MODEL ?? "gpt-5-mini";

const SCALES = [50, 500, 2_000, 5_000, 10_000];

describe("Aggregation Benchmark (real LLM)", () => {
  const allResults: EvalResult[] = [];

  for (const count of SCALES) {
    const records = generatePersonRecords(count);
    const { olderThan30 } = computePersonAnswers(records);
    const expected = String(olderThan30);
    const query =
      "How many people in the dataset are older than 30? Return only the number.";

<<<<<<< HEAD
    it(`JS-sandbox @ ${count} records`, async () => {
      const llm = new ChatOpenAI({ model: modelName, temperature: 0 });
      const result = await runJsSandboxEval({
=======
    it(`RLM @ ${count} records`, async () => {
      const llm = new ChatOpenAI({ model: modelName, temperature: 0 });
      const result = await runRlmEval({
>>>>>>> monorepo/main
        llm,
        task: `agg-${count}`,
        query,
        expected,
        context: records,
        maxDepth: 0,
      });
      allResults.push(result);
      console.log(
<<<<<<< HEAD
        `  JS-sandbox @ ${count}: acc=${result.accuracy} answer="${result.answer.slice(0, 40)}" total=${result.metrics.total_tokens}`,
=======
        `  RLM @ ${count}: acc=${result.accuracy} answer="${result.answer.slice(0, 40)}" total=${result.metrics.total_tokens}`,
>>>>>>> monorepo/main
      );
      // Accuracy recorded in results table; no hard assert
    }, 180_000);

<<<<<<< HEAD
    it(`Entity+JS @ ${count} records`, async () => {
      const llm = new ChatOpenAI({ model: modelName, temperature: 0 });
      const result = await runEntityWithJsEval({
=======
    it(`Agent+JS @ ${count} records`, async () => {
      const llm = new ChatOpenAI({ model: modelName, temperature: 0 });
      const result = await runAgentWithJsEval({
>>>>>>> monorepo/main
        llm,
        task: `agg-${count}`,
        query,
        expected,
        context: records,
      });
      allResults.push(result);
      console.log(
<<<<<<< HEAD
        `  Entity+JS @ ${count}: acc=${result.accuracy} answer="${result.answer.slice(0, 40)}" total=${result.metrics.total_tokens}`,
      );
    }, 180_000);

    it(`Entity+JS-meta @ ${count} records`, async () => {
      const llm = new ChatOpenAI({ model: modelName, temperature: 0 });
      const result = await runEntityMetaJsEval({
=======
        `  Agent+JS @ ${count}: acc=${result.accuracy} answer="${result.answer.slice(0, 40)}" total=${result.metrics.total_tokens}`,
      );
    }, 180_000);

    it(`Agent+JS-meta @ ${count} records`, async () => {
      const llm = new ChatOpenAI({ model: modelName, temperature: 0 });
      const result = await runAgentMetaJsEval({
>>>>>>> monorepo/main
        llm,
        task: `agg-${count}`,
        query,
        expected,
        context: records,
      });
      allResults.push(result);
      console.log(
<<<<<<< HEAD
        `  Entity+JS-meta @ ${count}: acc=${result.accuracy} answer="${result.answer.slice(0, 40)}" total=${result.metrics.total_tokens}`,
=======
        `  Agent+JS-meta @ ${count}: acc=${result.accuracy} answer="${result.answer.slice(0, 40)}" total=${result.metrics.total_tokens}`,
>>>>>>> monorepo/main
      );
      // Accuracy recorded in results table; no hard assert
    }, 180_000);

    it(`In-context @ ${count} records`, async () => {
      const llm = new ChatOpenAI({ model: modelName, temperature: 0 });
      const result = await runInContextEval({
        llm,
        task: `agg-${count}`,
        query,
        expected,
        context: records,
      });
      allResults.push(result);
      console.log(
        `  In-context @ ${count}: acc=${result.accuracy} answer="${result.answer.slice(0, 40)}" total=${result.metrics.total_tokens}`,
      );
    }, 180_000);
  }

  it("Scaling Analysis", () => {
    if (allResults.length === 0) return;
    printComparisonTable(allResults);

<<<<<<< HEAD
    // Sanity: JS-sandbox should count correctly at all scales
    const sandboxResults = allResults.filter((r) => r.approach === "js-sandbox");
    const sandboxAccuracy =
      sandboxResults.reduce((s, r) => s + r.accuracy, 0) / sandboxResults.length;
    expect(sandboxAccuracy).toBeGreaterThan(0.5);
=======
    // Sanity: RLM should count correctly at all scales
    const rlmResults = allResults.filter((r) => r.approach === "rlm");
    const rlmAccuracy =
      rlmResults.reduce((s, r) => s + r.accuracy, 0) / rlmResults.length;
    expect(rlmAccuracy).toBeGreaterThan(0.5);
>>>>>>> monorepo/main
  });
});
