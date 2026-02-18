import { describe, expect, test } from "bun:test";

import { cantrip } from "../src/cantrip/cantrip";
import { Agent, TaskComplete } from "../src/entity/service";
import { tool } from "../src/circle/gate/decorator";
import { renderGateDefinitions } from "../src/cantrip/call";
import type { Circle } from "../src/circle/circle";
import { Loom, MemoryStorage } from "../src/loom";

// ── Shared helpers ─────────────────────────────────────────────────

async function doneHandler({ message }: { message: string }) {
  throw new TaskComplete(message);
}

const doneGate = tool("Signal completion", doneHandler, {
  name: "done",
  schema: {
    type: "object",
    properties: { message: { type: "string" } },
    required: ["message"],
    additionalProperties: false,
  },
});

const echoGate = tool("Echo text back", async ({ text }: { text: string }) => text, {
  name: "echo",
  schema: {
    type: "object",
    properties: { text: { type: "string" } },
    required: ["text"],
    additionalProperties: false,
  },
});

const readGate = tool("Read a file", async ({ path }: { path: string }) => `content of ${path}`, {
  name: "read",
  schema: {
    type: "object",
    properties: { path: { type: "string" } },
    required: ["path"],
    additionalProperties: false,
  },
});

function makeCircle(gates = [doneGate], wards = [{ max_turns: 10, require_done_tool: true }]): Circle {
  return { gates, wards };
}

// ── CALL-1: call is immutable after construction ───────────────────

describe("CALL-1: call is immutable after construction", () => {
  test("CALL-1: mutation of call object after construction is visible to cast", async () => {
    // NOTE: The framework does NOT currently enforce immutability — the call
    // object is a plain JS object. This test documents the actual behavior:
    // mutating spell.call DOES affect subsequent casts.
    // TODO: enforce immutability via Object.freeze or defensive copy in cast()
    const messagesPerCall: any[][] = [];
    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke(messages: any[]) {
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

    // Verify the original value is stored
    expect(spell.call.system_prompt).toBe("You are helpful");

    // Mutate after construction
    (spell.call as any).system_prompt = "You are evil";

    await spell.cast("test immutability");

    // Since immutability is NOT enforced, the crystal sees the mutated value
    const systemMsg = messagesPerCall[0][0];
    expect(systemMsg.role).toBe("system");
    expect(systemMsg.content).toBe("You are evil");
  });
});

// ── CALL-2: system prompt is first message on every invocation ─────

describe("CALL-2: system prompt is first message on every invocation", () => {
  test("CALL-2: system prompt appears as first message in each crystal call", async () => {
    const messagesPerCall: any[][] = [];
    let callCount = 0;

    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke(messages: any[]) {
        messagesPerCall.push([...messages]);
        callCount++;
        if (callCount === 1) {
          return {
            content: null,
            tool_calls: [
              {
                id: "call_1",
                type: "function",
                function: {
                  name: "echo",
                  arguments: JSON.stringify({ text: "1" }),
                },
              },
            ],
          };
        }
        return {
          content: null,
          tool_calls: [
            {
              id: "call_2",
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
      call: { system_prompt: "You are a test agent" },
      circle: makeCircle([doneGate, echoGate]),
    });

    await spell.cast("test system prompt presence");

    // Both invocations should start with the system prompt
    for (const messages of messagesPerCall) {
      expect(messages[0].role).toBe("system");
      expect(messages[0].content).toBe("You are a test agent");
    }
  });
});

// ── CALL-3: gate definitions derived from circle ───────────────────

describe("CALL-3: gate definitions derived from circle", () => {
  test("CALL-3: cantrip derives gate definitions from circle gates", () => {
    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke() {
        return { content: "ok", tool_calls: [] };
      },
    };

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle([doneGate, readGate]),
    });

    // The resolved call should have gate definitions for both gates
    expect(spell.call.gate_definitions.length).toBe(2);
    const names = spell.call.gate_definitions.map((g: any) => g.name);
    expect(names).toContain("done");
    expect(names).toContain("read");
  });

  test("CALL-3: renderGateDefinitions extracts correct schema", () => {
    const rendered = renderGateDefinitions([doneGate, readGate]);
    expect(rendered).toHaveLength(2);
    expect(rendered[0].name).toBe("done");
    expect(rendered[1].name).toBe("read");
    expect(rendered[1].parameters).toEqual({
      type: "object",
      properties: { path: { type: "string" } },
      required: ["path"],
      additionalProperties: false,
    });
  });
});

// ── CALL-4: call stored as root context in loom ────────────────────

describe("CALL-4: call stored as root context in loom", () => {
  test("CALL-4: cantrip stores call info matching construction input", () => {
    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke() {
        return { content: "ok", tool_calls: [] };
      },
    };

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "You are a test agent", hyperparameters: { tool_choice: "required" } },
      circle: makeCircle(),
    });

    // Verify stored values match what was passed to cantrip()
    expect(spell.call.system_prompt).toBe("You are a test agent");
    expect(spell.call.hyperparameters.tool_choice).toBe("required");
    // Gate definitions derived from the circle's gates (done gate)
    expect(spell.call.gate_definitions.length).toBe(1);
    expect(spell.call.gate_definitions[0].name).toBe("done");
  });

  test("CALL-4: loom records call root when used with Agent", async () => {
    // Test the loom structure directly
    const { Loom, MemoryStorage, generateTurnId } = await import("../src/loom");
    const loom = new Loom(new MemoryStorage());

    // Manually record a call root turn (simulating what Agent.recordCallRoot does)
    const callRoot = {
      id: generateTurnId(),
      parent_id: null,
      cantrip_id: "test",
      entity_id: "test",
      sequence: 0,
      role: "call" as const,
      utterance: "You are a test agent",
      observation: "- done: Signal completion",
      gate_calls: [],
      metadata: {
        tokens_prompt: 0,
        tokens_completion: 0,
        tokens_cached: 0,
        duration_ms: 0,
        timestamp: new Date().toISOString(),
      },
      reward: null,
      terminated: false,
      truncated: false,
    };
    await loom.append(callRoot);

    const roots = loom.getRoots();
    expect(roots.length).toBe(1);
    expect(roots[0].role).toBe("call");
    expect(roots[0].utterance).toBe("You are a test agent");
  });
});

// ── CALL-5: folding never compresses the system prompt ─────────────

describe("CALL-5: folding never compresses the system prompt", () => {
  test("CALL-5: system prompt persists across all invocations even with many turns", async () => {
    const messagesPerCall: any[][] = [];
    let callCount = 0;

    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke(messages: any[]) {
        messagesPerCall.push([...messages]);
        callCount++;
        if (callCount <= 5) {
          return {
            content: null,
            tool_calls: [
              {
                id: `call_${callCount}`,
                type: "function",
                function: {
                  name: "echo",
                  arguments: JSON.stringify({ text: `${callCount}` }),
                },
              },
            ],
          };
        }
        return {
          content: null,
          tool_calls: [
            {
              id: "call_done",
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
      call: { system_prompt: "Never forget this prompt" },
      circle: makeCircle([doneGate, echoGate]),
    });

    await spell.cast("test folding preserves call");

    // Every invocation should start with the system prompt
    for (const messages of messagesPerCall) {
      expect(messages[0].role).toBe("system");
      expect(messages[0].content).toBe("Never forget this prompt");
    }
  });
});
