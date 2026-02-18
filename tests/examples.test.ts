import { describe, expect, test } from "bun:test";

describe("examples", () => {
  test("03_circle runs validation", async () => {
    // Circle is pure logic — no LLM needed.
    const { Circle, done, tool, max_turns, require_done } = await import("../src");

    const greet = tool("greet", async ({ name }: { name: string }) => `Hello, ${name}!`, {
      name: "greet",
      params: { name: "string" },
    });

    const circle = Circle({
      gates: [greet, done],
      wards: [max_turns(10)],
    });
    expect(circle.gates.length).toBe(2);
    expect(circle.wards.length).toBe(1);

    // Missing done gate throws
    expect(() => Circle({ gates: [greet], wards: [max_turns(10)] })).toThrow();

    // No wards throws
    expect(() => Circle({ gates: [greet, done], wards: [] })).toThrow();
  });

  test("05_loom runs without LLM", async () => {
    const { Loom, MemoryStorage, deriveThread, generateTurnId } = await import("../src");
    const loom = new Loom(new MemoryStorage());

    const turn = {
      id: generateTurnId(),
      parent_id: null,
      cantrip_id: "test",
      entity_id: "test",
      sequence: 1,
      utterance: "hello",
      observation: "hi",
      gate_calls: [],
      metadata: {
        tokens_prompt: 10, tokens_completion: 5, tokens_cached: 0,
        duration_ms: 100, timestamp: new Date().toISOString(),
      },
      reward: null,
      terminated: true,
      truncated: false,
    };
    await loom.append(turn);
    expect(loom.size).toBe(1);

    const thread = deriveThread(loom, turn.id);
    expect(thread.turns.length).toBe(1);
  });

  test("example files exist", async () => {
    const files = [
      "01_crystal.ts", "02_gate.ts", "03_circle.ts", "04_cantrip.ts",
      "05_loom.ts", "06_providers.ts", "07_gate_fs.ts", "08_gate_js.ts",
      "09_gate_browser.ts", "10_composition.ts", "11_folding.ts",
      "12_full_agent.ts", "13_acp.ts", "env.ts",
    ];
    for (const f of files) {
      const file = Bun.file(`examples/${f}`);
      expect(await file.exists()).toBe(true);
    }
  });
});
