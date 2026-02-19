import { describe, expect, test } from "bun:test";
import { loadEnv } from "./helpers/env";

loadEnv();

const hasAnthropicKey = !!process.env.ANTHROPIC_API_KEY;
const hasOpenAIKey = !!process.env.OPENAI_API_KEY;
const conditionalAnthropicTest = hasAnthropicKey ? test : test.skip;
const conditionalOpenAITest = hasOpenAIKey ? test : test.skip;

describe("examples", () => {
  test("all example files exist", async () => {
    const files = [
      "01_crystal.ts", "02_gate.ts", "03_circle.ts", "04_cantrip.ts",
      "05_loom.ts", "06_providers.ts", "07_conversation.ts", "08_gate_js.ts",
      "09_gate_browser.ts", "10_composition.ts", "11_folding.ts",
      "12_full_agent.ts", "13_acp.ts", "env.ts",
    ];
    for (const f of files) {
      const file = Bun.file(`examples/${f}`);
      expect(await file.exists()).toBe(true);
    }
  });

  test("all examples export main()", async () => {
    const examples = [
      "01_crystal", "02_gate", "03_circle", "04_cantrip",
      "05_loom", "06_providers", "07_conversation", "08_gate_js",
      "09_gate_browser", "10_composition", "11_folding",
      "12_full_agent", "13_acp",
    ];
    for (const name of examples) {
      const mod = await import(`../examples/${name}`);
      expect(typeof mod.main).toBe("function");
    }
  });

  // ── No-LLM examples: run directly ──────────────────────────────

  test("02_gate runs without LLM", async () => {
    const { main } = await import("../examples/02_gate");
    await main();
  });

  test("03_circle runs validation", async () => {
    const { main } = await import("../examples/03_circle");
    main();
  });

  test("05_loom runs without LLM", async () => {
    const { main } = await import("../examples/05_loom");
    await main();
  });

  test("11_folding runs without LLM", async () => {
    const { main } = await import("../examples/11_folding");
    await main();
  });

  // ── LLM examples (Anthropic): skip without API key ─────────────

  conditionalAnthropicTest("01_crystal runs with Anthropic", async () => {
    const { main } = await import("../examples/01_crystal");
    await main();
  }, 30_000);

  conditionalAnthropicTest("04_cantrip runs with Anthropic", async () => {
    const { main } = await import("../examples/04_cantrip");
    await main();
  }, 60_000);

  conditionalAnthropicTest("06_providers runs with Anthropic", async () => {
    const { main } = await import("../examples/06_providers");
    await main();
  }, 30_000);

  // Interactive examples — these call runRepl() or serveCantripACP(),
  // which require stdin/server. We verify they import cleanly.
  // Running them fully requires a separate harness.

  conditionalAnthropicTest("07_conversation imports cleanly", async () => {
    const mod = await import("../examples/07_conversation");
    expect(typeof mod.main).toBe("function");
  });

  conditionalAnthropicTest("08_gate_js imports cleanly", async () => {
    const mod = await import("../examples/08_gate_js");
    expect(typeof mod.main).toBe("function");
  });

  conditionalAnthropicTest("09_gate_browser imports cleanly", async () => {
    const mod = await import("../examples/09_gate_browser");
    expect(typeof mod.main).toBe("function");
  });

  conditionalAnthropicTest("12_full_agent imports cleanly", async () => {
    const mod = await import("../examples/12_full_agent");
    expect(typeof mod.main).toBe("function");
  });

  conditionalAnthropicTest("13_acp imports cleanly", async () => {
    const mod = await import("../examples/13_acp");
    expect(typeof mod.main).toBe("function");
  });

  // ── LLM examples (OpenAI): skip without API key ────────────────

  conditionalOpenAITest("10_composition runs with OpenAI", async () => {
    const { main } = await import("../examples/10_composition");
    await main();
  }, 60_000);
});
