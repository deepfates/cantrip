import { describe, expect, test } from "bun:test";

import { cantrip } from "../../src/cantrip/cantrip";
import { TaskComplete } from "../../src/entity/recording";
import { gate } from "../../src/circle/gate/decorator";
import { Circle } from "../../src/circle/circle";
import type { BoundGate } from "../../src/circle/gate/gate";

// ── Shared helpers ─────────────────────────────────────────────────

async function doneHandler({ message }: { message: string }) {
  throw new TaskComplete(message);
}

const doneGate = gate("Signal completion", doneHandler, {
  name: "done",
  schema: {
    type: "object",
    properties: { message: { type: "string" } },
    required: ["message"],
    additionalProperties: false,
  },
});

const ward = { max_turns: 10, require_done_tool: true };

function makeCircle(gates: BoundGate[] = [doneGate], wards = [ward]) {
  return Circle({ gates, wards });
}

// ── INTENT-1: casting without intent is invalid ────────────────────

describe("INTENT-1: casting without intent is invalid", () => {
  test("INTENT-1: cast with null intent throws", async () => {
    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query() {
        return {
          content: null,
          tool_calls: [
            {
              id: "call_1",
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({ message: "ok" }),
              },
            },
          ],
        };
      },
    };

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle(),
    });

    await expect(spell.cast(null as any)).rejects.toThrow(/intent/i);
  });

  test("INTENT-1: cast with empty string intent throws", async () => {
    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query() {
        return { content: "ok", tool_calls: [] };
      },
    };

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle(),
    });

    await expect(spell.cast("")).rejects.toThrow(/intent/i);
  });
});

// ── INTENT-2: intent appears as first user message ─────────────────

describe("INTENT-2: intent appears as first user message", () => {
  test("INTENT-2: crystal receives system prompt then user intent", async () => {
    const messagesPerCall: any[][] = [];
    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query(messages: any[]) {
        messagesPerCall.push([...messages]);
        return {
          content: null,
          tool_calls: [
            {
              id: "call_1",
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({ message: "ok" }),
              },
            },
          ],
        };
      },
    };

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "You are helpful" },
      circle: makeCircle(),
    });

    await spell.cast("my task");

    // First invocation should have: system message, then user message
    const messages = messagesPerCall[0];
    expect(messages[0].role).toBe("system");
    expect(messages[0].content).toBe("You are helpful");
    expect(messages[1].role).toBe("user");
    expect(messages[1].content).toBe("my task");
  });
});

// ── INTENT-3: intent is the sole input channel ─────────────────────
// DELETED: Redundant — every other test in this suite and others already
// proves that cast() accepts a string. This test added no unique assertion.
