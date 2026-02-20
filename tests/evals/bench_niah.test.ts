/**
 * Benchmark: Needle-in-a-Haystack (S-NIAH style)
 *
 * Uses real LLMs to find a SECRET_CODE hidden in text of increasing size.
 * Three approaches compared:
 * - JS-sandbox: context in sandbox, metadata-only output
 * - Entity+JS: context in sandbox, full output to LLM
 * - Entity+JS-meta: context in sandbox, metadata-only output (fair control)
 *
 * Requires OPENAI_API_KEY in .env (skips gracefully if missing).
 */
import { describe, test, expect } from "bun:test";
import { ChatOpenAI } from "../../src/crystal/providers/openai/chat";
import { generateHaystack } from "./generators";
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

const NEEDLE = 'SECRET_CODE: "foxtrot-tango-77"';
const EXPECTED = "foxtrot-tango-77";

const SCALES = [5_000, 25_000, 100_000, 500_000];

describe("NIAH Benchmark (real LLM)", () => {
  const allResults: EvalResult[] = [];

  for (const size of SCALES) {
    const { haystack } = generateHaystack({ size, needle: NEEDLE });
    const query =
      "Find the SECRET_CODE hidden in the text. Return only the code value.";

    it(`JS-sandbox @ ${(size / 1000).toFixed(0)}K`, async () => {
      const llm = new ChatOpenAI({ model: modelName, temperature: 0 });
      const result = await runJsSandboxEval({
        llm,
        task: `niah-${size}`,
        query,
        expected: EXPECTED,
        context: haystack,
        maxDepth: 0,
      });
      allResults.push(result);
      console.log(
        `  JS-sandbox @ ${size}: acc=${result.accuracy} total=${result.metrics.total_tokens} prompt=${result.metrics.total_prompt_tokens}`,
      );
      // Accuracy recorded in results table; no hard assert
    }, 180_000);

    it(`Entity+JS @ ${(size / 1000).toFixed(0)}K`, async () => {
      const llm = new ChatOpenAI({ model: modelName, temperature: 0 });
      const result = await runEntityWithJsEval({
        llm,
        task: `niah-${size}`,
        query,
        expected: EXPECTED,
        context: haystack,
      });
      allResults.push(result);
      console.log(
        `  Entity+JS @ ${size}: acc=${result.accuracy} total=${result.metrics.total_tokens} prompt=${result.metrics.total_prompt_tokens}`,
      );
      // Accuracy recorded in results table; no hard assert
    }, 180_000);

    it(`Entity+JS-meta @ ${(size / 1000).toFixed(0)}K`, async () => {
      const llm = new ChatOpenAI({ model: modelName, temperature: 0 });
      const result = await runEntityMetaJsEval({
        llm,
        task: `niah-${size}`,
        query,
        expected: EXPECTED,
        context: haystack,
      });
      allResults.push(result);
      console.log(
        `  Entity+JS-meta @ ${size}: acc=${result.accuracy} total=${result.metrics.total_tokens} prompt=${result.metrics.total_prompt_tokens}`,
      );
      // Accuracy recorded in results table; no hard assert
    }, 180_000);

    it(`In-context @ ${(size / 1000).toFixed(0)}K`, async () => {
      const llm = new ChatOpenAI({ model: modelName, temperature: 0 });
      const result = await runInContextEval({
        llm,
        task: `niah-${size}`,
        query,
        expected: EXPECTED,
        context: haystack,
      });
      allResults.push(result);
      console.log(
        `  In-context @ ${size}: acc=${result.accuracy} total=${result.metrics.total_tokens} prompt=${result.metrics.total_prompt_tokens}`,
      );
    }, 180_000);
  }

  it("Scaling Analysis", () => {
    if (allResults.length === 0) return;
    printComparisonTable(allResults);

    // Sanity: JS-sandbox should find the needle at most scales
    const sandboxResults = allResults.filter((r) => r.approach === "js-sandbox");
    const sandboxAccuracy =
      sandboxResults.reduce((s, r) => s + r.accuracy, 0) / sandboxResults.length;
    expect(sandboxAccuracy).toBeGreaterThanOrEqual(0.5);
  });
});
