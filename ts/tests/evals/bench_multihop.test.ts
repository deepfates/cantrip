/**
 * Benchmark: Multi-hop Reasoning
 *
 * Uses real LLMs to answer questions requiring connecting facts
 * from separate documents buried among distractors.
 *
 * Four approaches compared:
 * - JS-sandbox (depth=0): no sub-delegation
 * - JS-sandbox (depth=1): with sub-delegation
 * - Entity+JS: full output
 * - Entity+JS-meta: metadata-only output (fair control)
 *
 * Requires OPENAI_API_KEY in .env (skips gracefully if missing).
 */
import { describe, test, expect } from "bun:test";
import { ChatOpenAI } from "../../src/crystal/providers/openai/chat";
import { generateMultihopDocuments } from "./generators";
import {
  runJsSandboxEval,
  runEntityWithJsEval,
  runEntityMetaJsEval,
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

const SCALES = [20, 200, 1_000];

describe("Multi-hop Benchmark (real LLM)", () => {
  const allResults: EvalResult[] = [];

  for (const distractorCount of SCALES) {
    const dataset = generateMultihopDocuments(distractorCount);
    const { documents, targetCity, expectedAnswer } = dataset;
    const query = `What is the favorite color of the person who lives in ${targetCity}? The data is split across multiple documents — one document has the person's city, another has their color. You need to find the name first by city, then find the color by name. Return only the color.`;

    it(`JS-sandbox (depth=0) @ ${distractorCount}`, async () => {
      const llm = new ChatOpenAI({ model: modelName, temperature: 0 });
      const result = await runJsSandboxEval({
        llm,
        task: `mh-d0-${distractorCount}`,
        query,
        expected: expectedAnswer,
        context: documents,
        maxDepth: 0,
        approach: "js-sandbox-d0",
      });
      allResults.push(result);
      console.log(
        `  JS-sandbox(d=0) @ ${distractorCount}: acc=${result.accuracy} answer="${result.answer.slice(0, 40)}" total=${result.metrics.total_tokens}`,
      );
    }, 120_000);

    it(`JS-sandbox (depth=1) @ ${distractorCount}`, async () => {
      const llm = new ChatOpenAI({ model: modelName, temperature: 0 });
      const result = await runJsSandboxEval({
        llm,
        task: `mh-d1-${distractorCount}`,
        query,
        expected: expectedAnswer,
        context: documents,
        maxDepth: 1,
        approach: "js-sandbox-d1",
      });
      allResults.push(result);
      console.log(
        `  JS-sandbox(d=1) @ ${distractorCount}: acc=${result.accuracy} answer="${result.answer.slice(0, 40)}" total=${result.metrics.total_tokens}`,
      );
    }, 120_000);

    it(`Entity+JS @ ${distractorCount}`, async () => {
      const llm = new ChatOpenAI({ model: modelName, temperature: 0 });
      const result = await runEntityWithJsEval({
        llm,
        task: `mh-${distractorCount}`,
        query,
        expected: expectedAnswer,
        context: documents,
      });
      allResults.push(result);
      console.log(
        `  Entity+JS @ ${distractorCount}: acc=${result.accuracy} answer="${result.answer.slice(0, 40)}" total=${result.metrics.total_tokens}`,
      );
    }, 120_000);

    it(`Entity+JS-meta @ ${distractorCount}`, async () => {
      const llm = new ChatOpenAI({ model: modelName, temperature: 0 });
      const result = await runEntityMetaJsEval({
        llm,
        task: `mh-${distractorCount}`,
        query,
        expected: expectedAnswer,
        context: documents,
      });
      allResults.push(result);
      console.log(
        `  Entity+JS-meta @ ${distractorCount}: acc=${result.accuracy} answer="${result.answer.slice(0, 40)}" total=${result.metrics.total_tokens}`,
      );
    }, 120_000);

    it(`In-context @ ${distractorCount}`, async () => {
      const llm = new ChatOpenAI({ model: modelName, temperature: 0 });
      const result = await runInContextEval({
        llm,
        task: `mh-${distractorCount}`,
        query,
        expected: expectedAnswer,
        context: documents,
      });
      allResults.push(result);
      console.log(
        `  In-context @ ${distractorCount}: acc=${result.accuracy} answer="${result.answer.slice(0, 40)}" total=${result.metrics.total_tokens}`,
      );
    }, 120_000);
  }

  it("Scaling Analysis", () => {
    if (allResults.length === 0) return;
    printComparisonTable(allResults);

    console.log("\nAccuracy by approach:");
    const approaches = [...new Set(allResults.map((r) => r.approach))];
    for (const approach of approaches) {
      const results = allResults.filter((r) => r.approach === approach);
      const correct = results.filter((r) => r.accuracy === 1).length;
      console.log(`  ${approach}: ${correct}/${results.length} correct`);
    }

    // Sanity: JS-sandbox should link facts correctly at most scales
    const sandboxResults = allResults.filter((r) => r.approach.startsWith("js-sandbox"));
    const sandboxAccuracy =
      sandboxResults.reduce((s, r) => s + r.accuracy, 0) / sandboxResults.length;
    expect(sandboxAccuracy).toBeGreaterThan(0.5);
  });
});
