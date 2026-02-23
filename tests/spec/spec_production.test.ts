import { describe, expect, test } from "bun:test";

import { TaskComplete } from "../../src/entity/errors";
import { Entity } from "../../src/cantrip/entity";
import { Circle } from "../../src/circle/circle";
import { cantrip } from "../../src/cantrip/cantrip";
import { gate } from "../../src/circle/gate/decorator";

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

const echoGate = gate("Echo text back", async ({ text }: { text: string }) => text, {
  name: "echo",
  schema: {
    type: "object",
    properties: { text: { type: "string" } },
    required: ["text"],
    additionalProperties: false,
  },
});

/** Helper to create an Entity with minimal boilerplate. */
function createEntity(opts: {
  llm: any;
  gates: any[];
  wards?: any[];
  system_prompt?: string | null;
  retry?: { max_retries?: number; base_delay?: number; max_delay?: number };
}) {
  const circle = Circle({
    gates: opts.gates,
    wards: opts.wards ?? [{ max_turns: 10, require_done_tool: true }],
  });
  return new Entity({
    crystal: opts.llm,
    call: {
      system_prompt: opts.system_prompt ?? null,
      hyperparameters: { tool_choice: "auto" },
      gate_definitions: [],
    },
    circle,
    dependency_overrides: null,
    retry: opts.retry,
  });
}

// ── PROD-1: protocol does not alter entity behavior ────────────────
// DELETED: With deterministic mocks, two identical cantrips always produce
// the same result trivially. This test was meaningful only with real providers
// where observability config could introduce side effects. Skipped per audit.

// ── PROD-2: retried invocation appears as single turn ──────────────

describe("PROD-2: retried invocation appears as single turn", () => {
  test("PROD-2: retries on 429 and produces single result", async () => {
    let calls = 0;
    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query() {
        calls++;
        if (calls < 3) {
          const err: any = new Error("rate limited");
          err.status_code = 429;
          throw err;
        }
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

    const entity = createEntity({
      llm: crystal as any,
      gates: [doneGate],
      system_prompt: "test",
      retry: { max_retries: 3, base_delay: 0, max_delay: 0 },
    });

    const result = await entity.cast("test retry");
    expect(result).toBe("ok");
    expect(calls).toBe(3); // 2 failures + 1 success
  });

  test("PROD-2: retried invocation produces single result (not two)", async () => {
    let calls = 0;
    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query() {
        calls++;
        if (calls === 1) {
          const err: any = new Error("rate limited");
          err.status_code = 429;
          throw err;
        }
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

    const entity = createEntity({
      llm: crystal as any,
      gates: [doneGate],
      system_prompt: "test",
      retry: { max_retries: 3, base_delay: 0, max_delay: 0 },
    });

    const result = await entity.cast("test retry");
    expect(result).toBe("ok");
    // Despite the retry, history should reflect a single completed interaction
    // (not duplicate assistant messages from the retry)
    const assistantMessages = entity.history.filter((m) => m.role === "assistant");
    expect(assistantMessages.length).toBe(1);
  });
});

// ── PROD-3: cumulative token tracking ──────────────────────────────

describe("PROD-3: cumulative token tracking", () => {
  test("PROD-3: usage tracker accumulates tokens across turns", async () => {
    let callCount = 0;

    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query() {
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
            usage: { prompt_tokens: 100, completion_tokens: 50 },
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
          usage: { prompt_tokens: 200, completion_tokens: 30 },
        };
      },
    };

    const entity = createEntity({
      llm: crystal as any,
      gates: [doneGate, echoGate],
      system_prompt: "test",
    });

    await entity.cast("test usage tracking");

    const usage = await entity.get_usage();
    // Should have accumulated usage from both calls
    expect(usage.total_prompt_tokens).toBe(300);
    expect(usage.total_completion_tokens).toBe(80);
  });
});

// ── PROD-4: folding triggered automatically near context limit ─────
// TODO: untestable with mocks — folding is triggered by token count thresholds
// near the context limit, which cannot be simulated with deterministic mocks
// that have zero-length messages. A real integration test with a provider that
// returns usage data would be needed to verify folding compresses messages.

// ── PROD-5: ephemeral gate full result stored in loom ──────────────

describe("PROD-5: ephemeral gate full result stored in loom", () => {
  test("PROD-5: ephemeral tool messages are destroyed after subsequent use", async () => {
    // Ephemeral with value 1 means: destroy the tool message after 1 newer
    // invocation of the same tool. So we need 2 calls to the ephemeral gate.
    const ephemeralGate = gate("Read ephemeral", async () => "very large content here...", {
      name: "read_ephemeral",
      schema: {
        type: "object",
        properties: {},
        required: [],
        additionalProperties: false,
      },
      ephemeral: 1,
    });

    let callCount = 0;

    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query() {
        callCount++;
        if (callCount <= 2) {
          return {
            content: null,
            tool_calls: [
              {
                id: `call_${callCount}`,
                type: "function",
                function: {
                  name: "read_ephemeral",
                  arguments: "{}",
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

    const entity = createEntity({
      llm: crystal as any,
      gates: [doneGate, ephemeralGate],
      system_prompt: "test",
    });

    const result = await entity.cast("test ephemeral");
    expect(result).toBe("ok");

    // The first ephemeral tool message should be destroyed, second still active
    const toolMessages = entity.history.filter((m) => m.role === "tool") as any[];
    // Should have at least 2 ephemeral tool messages (+ possibly done tool message)
    expect(toolMessages.length).toBeGreaterThanOrEqual(2);
    // First ephemeral call should be destroyed
    expect(toolMessages[0].destroyed).toBe(true);
    // Second ephemeral call should NOT be destroyed yet
    expect(toolMessages[1].destroyed).toBe(false);
  });
});
