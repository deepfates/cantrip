import { describe, expect, test } from "bun:test";

import { loadEnv } from "./helpers/env";
import { main as coreLoopMain } from "../examples/01_core_loop";
import { main as quickStartMain } from "../examples/02_quick_start";
import { main as providersMain } from "../examples/03_providers";
import { main as diMain } from "../examples/04_dependency_injection";
import { main as fsAgentMain } from "../examples/05_fs_agent";
import { main as jsAgentMain } from "../examples/06_js_agent";
import { main as browserAgentMain } from "../examples/07_browser_agent";
import { main as fullAgentMain } from "../examples/08_full_agent";

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
    "providers example runs with Anthropic key",
    async () => {
      const result = await providersMain();
      expect(result).toBeUndefined(); // logs to console, returns void
    },
    { timeout: 20_000 },
  );

  // These are interactive REPLs, so we just check they're importable
  test("fs_agent example is importable", () => {
    expect(typeof fsAgentMain).toBe("function");
  });

  test("js_agent example is importable", () => {
    expect(typeof jsAgentMain).toBe("function");
  });

  test("browser_agent example is importable", () => {
    expect(typeof browserAgentMain).toBe("function");
  });

  test("full_agent example is importable", () => {
    expect(typeof fullAgentMain).toBe("function");
  });
});
