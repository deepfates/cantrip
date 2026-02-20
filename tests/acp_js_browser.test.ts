/**
 * Test for ACP RLM Browser example
 * 
 * Verifies that the module can be imported and has the expected structure.
 * Full integration tests require spawning browser processes and are better
 * suited for manual testing or CI with proper browser setup.
 */

import { describe, test, expect } from "bun:test";
import { ChatAnthropic } from "../src/crystal/providers/anthropic/chat";
import { createRlmAgent, createRlmAgentWithMemory } from "../src/circle/recipe/rlm";
import { BrowserContext } from "../src/circle/medium/browser/context";

describe("ACP RLM Browser Agent", () => {
  test("createRlmAgent with browserContext option is defined", () => {
    expect(createRlmAgent).toBeDefined();
    expect(typeof createRlmAgent).toBe("function");
  });

  test("createRlmAgentWithMemory with browserContext option is defined", () => {
    expect(createRlmAgentWithMemory).toBeDefined();
    expect(typeof createRlmAgentWithMemory).toBe("function");
  });

  test("BrowserContext.create is defined", () => {
    expect(BrowserContext.create).toBeDefined();
    expect(typeof BrowserContext.create).toBe("function");
  });

  test("example file exists and is readable", async () => {
    const file = Bun.file("examples/13_acp.ts");
    expect(await file.exists()).toBe(true);
    const content = await file.text();
    expect(content).toContain("serveCantripACP");
    // ACP example uses JS medium (not browser-as-gate)
    expect(content).toContain("medium: js(");
  });
});
