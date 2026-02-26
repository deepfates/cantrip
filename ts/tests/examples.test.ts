import { describe, expect, test } from "bun:test";

import { loadEnv } from "./helpers/env";
import { main as coreLoopMain } from "../examples/01_core_loop";
import { main as quickStartMain } from "../examples/02_quick_start";
import { main as providersMain } from "../examples/03_providers";
import { main as diMain } from "../examples/04_dependency_injection";

loadEnv();

const hasAnthropicKey = Boolean(process.env.ANTHROPIC_API_KEY);
const itAnthropic = hasAnthropicKey ? test : test.skip;

describe("examples", () => {
  test("01_core_loop runs", async () => {
    const result = await coreLoopMain();
    expect(result).toBe("Result is 5");
  });

  test("04_dependency_injection runs", async () => {
    const result = await diMain();
    expect(result).toContain("Executed:");
  });

  itAnthropic(
    "02_quick_start runs",
    async () => {
      const result = await quickStartMain();
      expect(result).toBeTruthy();
    },
    { timeout: 20_000 },
  );

  itAnthropic(
    "03_providers runs",
    async () => {
      const result = await providersMain();
      expect(result).toBeUndefined(); // logs to console, returns void
    },
    { timeout: 20_000 },
  );
});
