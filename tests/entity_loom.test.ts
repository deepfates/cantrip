import { describe, expect, test } from "bun:test";

import { Entity } from "../src/cantrip/entity";
import { cantrip } from "../src/cantrip/cantrip";
import { TaskComplete } from "../src/entity/recording";
import { gate } from "../src/circle/gate/decorator";
import { MemoryStorage, Loom } from "../src/loom";
import { Circle } from "../src/circle/circle";
import type { Ward } from "../src/circle/ward";
import type { BoundGate } from "../src/circle/gate/gate";

// ── Helpers ──────────────────────────────────────────────────────────

async function doneHandler({ message }: { message: string }) {
  throw new TaskComplete(message);
}

const doneGate = gate("Done", doneHandler, {
  name: "done",
  schema: {
    type: "object",
    properties: { message: { type: "string" } },
    required: ["message"],
    additionalProperties: false,
  },
});

const ward: Ward = { max_turns: 10, require_done_tool: true };

function makeCircle(gates: BoundGate[] = [doneGate], wards = [ward]) {
  return Circle({ gates, wards });
}

function makeLlm(responses: (() => any)[]) {
  let callIndex = 0;
  return {
    model: "dummy",
    provider: "dummy",
    name: "dummy",
    async query(messages: any[]) {
      const fn = responses[callIndex];
      if (!fn) throw new Error(`Unexpected LLM call #${callIndex}`);
      callIndex++;
      return fn();
    },
  };
}

// ── Tests ────────────────────────────────────────────────────────────

describe("Entity loom integration", () => {
  test("Entity records turns to loom when loom is provided", async () => {
    const storage = new MemoryStorage();
    const loom = new Loom(storage);

    const crystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "done",
              arguments: JSON.stringify({ message: "finished" }),
            },
          },
        ],
      }),
    ]);

    const entity = new Entity({
      crystal: crystal as any,
      call: {
        system_prompt: "You are a test entity.",
        hyperparameters: { tool_choice: "auto" },
        gate_definitions: [],
      },
      circle: makeCircle(),
      dependency_overrides: null,
      loom,
      cantrip_id: "test-cantrip",
      entity_id: "test-entity",
    });

    await entity.cast("hello");

    const turns = await storage.getAll();
    // Should have at least the call root + one turn
    expect(turns.length).toBeGreaterThanOrEqual(1);
    // The root turn should be a "call" role
    expect(turns[0].role).toBe("call");
    expect(turns[0].cantrip_id).toBe("test-cantrip");
    expect(turns[0].entity_id).toBe("test-entity");
  });

  test("Entity works without loom (no recording)", async () => {
    const crystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "done",
              arguments: JSON.stringify({ message: "no loom" }),
            },
          },
        ],
      }),
    ]);

    const entity = new Entity({
      crystal: crystal as any,
      call: {
        system_prompt: "test",
        hyperparameters: { tool_choice: "auto" },
        gate_definitions: [],
      },
      circle: makeCircle(),
      dependency_overrides: null,
    });

    const result = await entity.cast("hello");
    expect(result).toBe("no loom");
  });

  test("cantrip invoke() passes loom through to Entity", async () => {
    const storage = new MemoryStorage();
    const loom = new Loom(storage);

    const crystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "done",
              arguments: JSON.stringify({ message: "via cantrip" }),
            },
          },
        ],
      }),
    ]);

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle(),
      loom,
      cantrip_id: "cantrip-test",
    });

    const entity = spell.invoke();
    await entity.cast("hello");

    const turns = await storage.getAll();
    expect(turns.length).toBeGreaterThanOrEqual(1);
    expect(turns[0].cantrip_id).toBe("cantrip-test");
  });

  test("Entity uses configurable retry values", async () => {
    const crystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "done",
              arguments: JSON.stringify({ message: "with retry config" }),
            },
          },
        ],
      }),
    ]);

    // Just verify it doesn't crash with custom retry config
    const entity = new Entity({
      crystal: crystal as any,
      call: {
        system_prompt: "test",
        hyperparameters: { tool_choice: "auto" },
        gate_definitions: [],
      },
      circle: makeCircle(),
      dependency_overrides: null,
      retry: {
        max_retries: 3,
        base_delay: 0.5,
        max_delay: 30.0,
      },
    });

    const result = await entity.cast("hello");
    expect(result).toBe("with retry config");
  });

  test("Entity records multiple turns with parent chaining", async () => {
    const storage = new MemoryStorage();
    const loom = new Loom(storage);

    let callCount = 0;
    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query(messages: any[]) {
        callCount++;
        return {
          content: null,
          tool_calls: [
            {
              id: `call_${callCount}`,
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({ message: `result-${callCount}` }),
              },
            },
          ],
        };
      },
    };

    const entity = new Entity({
      crystal: crystal as any,
      call: {
        system_prompt: "test",
        hyperparameters: { tool_choice: "auto" },
        gate_definitions: [],
      },
      circle: makeCircle(),
      dependency_overrides: null,
      loom,
      cantrip_id: "multi-turn",
      entity_id: "entity-1",
    });

    await entity.cast("first");
    await entity.cast("second");

    const turns = await storage.getAll();
    // Root + at least 2 turn records
    expect(turns.length).toBeGreaterThanOrEqual(2);
    // Root should have no parent
    expect(turns[0].parent_id).toBeNull();
    // Subsequent turns should chain
    if (turns.length >= 3) {
      expect(turns[2].parent_id).toBe(turns[1].id);
    }
  });
});
