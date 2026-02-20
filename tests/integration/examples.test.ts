import { describe, expect, test } from "bun:test";
import { loadEnv } from "../helpers/env";

loadEnv();

const hasAnthropicKey = !!process.env.ANTHROPIC_API_KEY;
const hasOpenAIKey = !!process.env.OPENAI_API_KEY;

describe("examples", () => {
  // ── No-LLM examples: deterministic, always run ─────────────────

  test("02_gate: add returns 5, done fires TaskComplete", async () => {
    const { main } = await import("../../examples/02_gate");
    const result = await main();
    expect(String(result.sum)).toBe("5");
    expect(result.doneMessage).toBe("All done");
  });

  test("03_circle: validates gate names and error invariants", async () => {
    const { main } = await import("../../examples/03_circle");
    const result = main();
    expect(result.gateNames).toContain("greet");
    expect(result.gateNames).toContain("done");
    expect(result.missingDoneError).toBeString();
    expect(result.noWardsError).toBeString();
  });

  test("05_ward: wards compose correctly", async () => {
    const { main } = await import("../../examples/05_ward");
    const result = main();
    expect(result.resolved.max_turns).toBe(10);
    expect(result.resolved.require_done_tool).toBe(true);
    expect(result.resolved.max_depth).toBe(3);
    expect(result.composedMaxTurns).toBe(10);
    expect(result.orRequireDone).toBe(true);
  });

  test("11_folding: builds thread and partitions for folding", async () => {
    const { main } = await import("../../examples/11_folding");
    const result = await main();
    expect(result.turnCount).toBe(6);
    expect(result.totalTokens).toBeGreaterThan(0);
    expect(result.needsFolding).toBe(true);
    expect(result.foldCount + result.keepCount).toBe(6);
  });

  // ── LLM examples (Anthropic): skip without API key ─────────────

  test.skipIf(!hasAnthropicKey)("01_crystal: raw model call returns content", async () => {
    const { main } = await import("../../examples/01_crystal");
    const result = await main();
    expect(result).not.toBeNull();
    expect(typeof result).toBe("string");
    expect(result!.length).toBeGreaterThan(0);
  }, 30_000);

  test.skipIf(!hasAnthropicKey)("04_cantrip: casts and returns results", async () => {
    const { main } = await import("../../examples/04_cantrip");
    const result = await main();
    expect(result.result).toBeTruthy();
    expect(result.result2).toBeTruthy();
  }, 60_000);

  test.skipIf(!hasAnthropicKey)("06_providers: provider-swappable cantrip returns result", async () => {
    const { main } = await import("../../examples/06_providers");
    const result = await main();
    expect(result).toBeTruthy();
  }, 30_000);

  test.skipIf(!hasAnthropicKey)("08_js_medium: JS sandbox returns answer", async () => {
    const { main } = await import("../../examples/08_js_medium");
    const result = await main();
    expect(typeof result).toBe("string");
    expect(result.length).toBeGreaterThan(0);
  }, 60_000);

  // ── Interactive/server examples ─────────────────────────────────
  // These call runRepl() or serveCantripACP() which need stdin/server.
  // We verify they export a callable main (can't run fully in CI).

  test("07_conversation: exports callable main", async () => {
    const mod = await import("../../examples/07_conversation");
    expect(typeof mod.main).toBe("function");
  });

  test("09_browser_medium: exports callable main", async () => {
    const mod = await import("../../examples/09_browser_medium");
    expect(typeof mod.main).toBe("function");
  });

  test("12_full_agent: exports callable main", async () => {
    const mod = await import("../../examples/12_full_agent");
    expect(typeof mod.main).toBe("function");
  });

  test("13_acp: exports callable main", async () => {
    const mod = await import("../../examples/13_acp");
    expect(typeof mod.main).toBe("function");
  });

  // ── LLM examples (OpenAI): skip without API key ────────────────

  test.skipIf(!hasOpenAIKey)("10_composition: finds data in JS sandbox", async () => {
    const { main } = await import("../../examples/10_composition");
    const result = await main();
    expect(typeof result).toBe("string");
    expect(result.length).toBeGreaterThan(0);
  }, 60_000);
});
