import { describe, expect, test } from "bun:test";

import { loadEnv } from "./helpers/env";
import { main as coreLoopMain } from "../examples/core_loop";
import { main as diMain } from "../examples/dependency_injection";
import { main as quickStartMain } from "../examples/quick_start";
import { main as batteriesOffMain } from "../examples/batteries_off";
import { main as claudeCodeMain } from "../examples/claude_code";

loadEnv();

const hasAnthropicKey = Boolean(process.env.ANTHROPIC_API_KEY);
const itAnthropic = hasAnthropicKey ? test : test.skip;

describe("examples", () => {
  test("core loop runs", async () => {
    const result = await coreLoopMain();
    expect(result).toBe("Result is 5");
  });

  test("dependency injection runs", async () => {
    const result = await diMain();
    expect(result).toContain("Executed:");
  });

  itAnthropic(
    "quick_start runs with Anthropic key",
    async () => {
      const result = await quickStartMain();
      expect(result).toBeTruthy();
    },
    { timeout: 20_000 },
  );

  itAnthropic(
    "batteries_off runs with Anthropic key",
    async () => {
      const result = await batteriesOffMain();
      expect(result).toBeTruthy();
    },
    { timeout: 20_000 },
  );

  test("claude_code example is importable", () => {
    expect(typeof claudeCodeMain).toBe("function");
  });
});
