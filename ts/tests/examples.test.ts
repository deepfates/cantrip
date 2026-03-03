import { describe, expect, test } from "bun:test";

import { loadEnv } from "./helpers/env";
import { main as coreLoopMain } from "../examples/02_gate";
import { main as quickStartMain } from "../examples/04_cantrip";
import { main as providersMain } from "../examples/06_providers";
import { main as diMain } from "../examples/12_full_agent";

loadEnv();

const hasAnthropicKey = Boolean(process.env.ANTHROPIC_API_KEY);
const runLiveLlmExamples = process.env.RUN_LIVE_LLM_TESTS === "1";
const itAnthropic = hasAnthropicKey && runLiveLlmExamples ? test : test.skip;

describe("examples", () => {
  test("01_core_loop runs", async () => {
    const result = await coreLoopMain();
    expect(result).toEqual({ sum: "5", doneMessage: "All done" });
  });

  test("04_dependency_injection runs", async () => {
    const result = await diMain();
    expect(result).toBeTruthy();
  });

  itAnthropic(
    "02_quick_start runs",
    async () => {
      const result = await quickStartMain();
      expect(result).toBeTruthy();
    },
    { timeout: 20_000 },
  );

  test(
    "03_providers runs",
    async () => {
      process.env.CANTRIP_FAKE_LLM = "1";
      try {
        const result = await providersMain();
        expect(result).toContain("15");
      } finally {
        delete process.env.CANTRIP_FAKE_LLM;
      }
    },
    { timeout: 20_000 },
  );
});
