import { describe, expect, test } from "bun:test";

import { cantrip } from "../../src/cantrip/cantrip";
import { TaskComplete } from "../../src/entity/errors";
import { gate } from "../../src/circle/gate/decorator";
import { Circle } from "../../src/circle/circle";
import type { BoundGate } from "../../src/circle/gate/gate";
import { max_turns, require_done, max_depth, exclude_gate, resolveWards, type Ward } from "../../src/circle/ward";

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

function makeCircle(gates: BoundGate[] = [doneGate], wards: Ward[] = [{ max_turns: 10, require_done_tool: true }]) {
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

// ── CIRCLE-1: circle must have done gate ───────────────────────────

describe("CIRCLE-1: circle must have done gate", () => {
  test("CIRCLE-1: Circle constructor throws when no done gate present", () => {
    const notDone = gate("Not done", async () => "ok", {
      name: "other",
      schema: { type: "object", properties: {}, additionalProperties: false },
    });
    expect(() =>
      Circle({
        gates: [notDone],
        wards: [{ max_turns: 10, require_done_tool: false }],
      }),
    ).toThrow(/done/i);
  });

  test("CIRCLE-1: Circle constructor throws when gates array is empty", () => {
    expect(() =>
      Circle({
        gates: [],
        wards: [{ max_turns: 10, require_done_tool: false }],
      }),
    ).toThrow(/done/i);
  });

  test("CIRCLE-1: cantrip also validates done gate", () => {
    const crystal = makeLlm([]);
    const notDone = gate("Not done", async () => "ok", {
      name: "other",
      schema: { type: "object", properties: {}, additionalProperties: false },
    });
    expect(() =>
      cantrip({
        crystal: crystal as any,
        call: { system_prompt: "test" },
        circle: { gates: [notDone], wards: [{ max_turns: 10, require_done_tool: false }] } as any,
      }),
    ).toThrow(/done/i);
  });
});

// ── CIRCLE-2: circle must have termination ward ────────────────────

describe("CIRCLE-2: circle must have termination ward", () => {
  test("CIRCLE-2: Circle constructor throws when wards array is empty", () => {
    expect(() =>
      Circle({ gates: [doneGate], wards: [] }),
    ).toThrow(/ward/i);
  });
});

// ── CIRCLE-3: gate execution is synchronous from entity perspective ─

describe("CIRCLE-3: gate execution is synchronous from entity perspective", () => {
  test("CIRCLE-3: async gate results are available in next invocation", async () => {
    const messagesPerCall: any[][] = [];
    let callCount = 0;

    const slowGate = gate("Slow gate", async ({ delay_ms }: { delay_ms: number }) => {
      // Simulate async work
      await new Promise((resolve) => setTimeout(resolve, 10));
      return "completed";
    }, {
      name: "slow_gate",
      schema: {
        type: "object",
        properties: { delay_ms: { type: "integer" } },
        required: ["delay_ms"],
        additionalProperties: false,
      },
    });

    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query(messages: any[]) {
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
                  name: "slow_gate",
                  arguments: JSON.stringify({ delay_ms: 100 }),
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
      call: { system_prompt: "test" },
      circle: makeCircle([doneGate, slowGate]),
    });

    const result = await spell.cast("test sync");
    expect(result).toBe("ok");

    // Second invocation should see the slow_gate result
    const secondMessages = messagesPerCall[1];
    const hasCompleted = secondMessages.some(
      (m: any) => typeof m.content === "string" && m.content.includes("completed"),
    );
    expect(hasCompleted).toBe(true);
  });
});

// ── CIRCLE-4: gate results visible in context ──────────────────────

describe("CIRCLE-4: gate results visible in context", () => {
  test("CIRCLE-4: echo gate result appears in next crystal invocation", async () => {
    const messagesPerCall: any[][] = [];
    let callCount = 0;

    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query(messages: any[]) {
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
                  arguments: JSON.stringify({ text: "visible result" }),
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
      call: { system_prompt: "test" },
      circle: makeCircle([doneGate, echoGate]),
    });

    await spell.cast("test visibility");

    // Second invocation should contain the echo result
    const secondMessages = messagesPerCall[1];
    const hasVisibleResult = secondMessages.some(
      (m: any) => typeof m.content === "string" && m.content.includes("visible result"),
    );
    expect(hasVisibleResult).toBe(true);
  });
});

// ── CIRCLE-5: gate errors returned as observations ─────────────────

describe("CIRCLE-5: gate errors returned as observations", () => {
  test("CIRCLE-5: failing gate returns error, entity can recover", async () => {
    const failingGate = gate("Failing gate", async () => {
      throw new Error("something went wrong");
    }, {
      name: "failing_gate",
      schema: {
        type: "object",
        properties: {},
        required: [],
        additionalProperties: false,
      },
    });

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
                  name: "failing_gate",
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
              id: "call_2",
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({ message: "recovered" }),
              },
            },
          ],
        };
      },
    };

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle([doneGate, failingGate]),
    });

    const result = await spell.cast("test error handling");
    expect(result).toBe("recovered");
    expect(callCount).toBe(2);
  });
});

// ── CIRCLE-6: wards enforced by circle not entity ──────────────────
// NOTE: This tests max_turns ward enforcement — the circle truncates the entity
// loop regardless of what the entity wants. Framework-level ward-based gate
// removal (e.g., removing gates when a ward condition is met) is not yet
// implemented. TODO: test ward-based gate removal when framework supports it.

describe("CIRCLE-6: wards enforced by circle not entity", () => {
  test("CIRCLE-6: max_turns ward truncates entity loop even without done", async () => {
    let callCount = 0;
    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query() {
        callCount++;
        return {
          content: null,
          tool_calls: [
            {
              id: `call_${callCount}`,
              type: "function",
              function: {
                name: "echo",
                arguments: JSON.stringify({ text: "attempt" }),
              },
            },
          ],
        };
      },
    };

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle(
        [doneGate, echoGate],
        [{ max_turns: 1, require_done_tool: false }],
      ),
    });

    // The ward (max_turns=1) should truncate the loop after 1 turn
    // even though the entity never calls done
    const result = await spell.cast("test ward enforcement");
    // Result indicates truncation, not normal termination
    expect(result).toContain("Max iterations reached");
    // Entity was cut off by the circle's ward, not by its own choice
    expect(callCount).toBeGreaterThanOrEqual(1);
  });
});

// ── CIRCLE-7: multiple gate calls in one utterance executed in order ─

describe("CIRCLE-7: multiple gate calls in one utterance executed in order", () => {
  test("CIRCLE-7: gates execute in the order they appear in tool_calls", async () => {
    const gateCallOrder: string[] = [];

    const echoTracked = gate("Echo", async ({ text }: { text: string }) => {
      gateCallOrder.push(`echo:${text}`);
      return text;
    }, {
      name: "echo",
      schema: {
        type: "object",
        properties: { text: { type: "string" } },
        required: ["text"],
        additionalProperties: false,
      },
    });

    const doneTracked = gate("Done", async ({ message }: { message: string }) => {
      gateCallOrder.push("done");
      throw new TaskComplete(message);
    }, {
      name: "done",
      schema: {
        type: "object",
        properties: { message: { type: "string" } },
        required: ["message"],
        additionalProperties: false,
      },
    });

    const crystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "echo",
              arguments: JSON.stringify({ text: "first" }),
            },
          },
          {
            id: "call_2",
            type: "function",
            function: {
              name: "echo",
              arguments: JSON.stringify({ text: "second" }),
            },
          },
          {
            id: "call_3",
            type: "function",
            function: {
              name: "done",
              arguments: JSON.stringify({ message: "ok" }),
            },
          },
        ],
      }),
    ]);

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle([doneTracked, echoTracked]),
    });

    await spell.cast("test ordering");

    expect(gateCallOrder[0]).toBe("echo:first");
    expect(gateCallOrder[1]).toBe("echo:second");
    expect(gateCallOrder[2]).toBe("done");
  });
});

// ── CIRCLE-8: done gate returns its argument as the result ─────────

describe("CIRCLE-8: done gate returns its argument as the result", () => {
  test("CIRCLE-8: done gate argument becomes cast result", async () => {
    const crystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "done",
              arguments: JSON.stringify({ message: "the final answer" }),
            },
          },
        ],
      }),
    ]);

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle(),
    });

    const result = await spell.cast("test done result");
    expect(result).toBe("the final answer");
  });
});

// ── CIRCLE-9: sandbox state persists across turns in code circle ───
// NOTE: Code circle is an advanced feature; testing with standard gates

// ── CIRCLE-10: gate dependencies injected at construction ──────────

describe("CIRCLE-10: gate dependencies injected at construction", () => {
  test("CIRCLE-10: gates can receive dependency overrides via Depends", async () => {
    const { Depends } = await import("../../src/circle/gate/depends");

    // Create a named factory function so Record-based overrides can match by name
    function fsRoot() { return "/default/root"; }

    const readGateWithDep = gate(
      "Read with deps",
      async ({ path }: { path: string }, deps: any) => {
        return deps.root ? `${deps.root}/${path}` : path;
      },
      {
        name: "read_dep",
        schema: {
          type: "object",
          properties: { path: { type: "string" } },
          required: ["path"],
          additionalProperties: false,
        },
        dependencies: {
          root: new Depends(fsRoot),
        },
      },
    );

    let callCount = 0;
    const messagesPerCall: any[][] = [];
    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query(messages: any[]) {
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
                  name: "read_dep",
                  arguments: JSON.stringify({ path: "test.txt" }),
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
      call: { system_prompt: "test" },
      circle: makeCircle([doneGate, readGateWithDep]),
      dependency_overrides: { fsRoot: () => "/test/data" },
    });

    await spell.cast("read test.txt");

    // The second invocation should see the result with the injected root
    const secondMessages = messagesPerCall[1];
    const hasInjectedPath = secondMessages.some(
      (m: any) => typeof m.content === "string" && m.content.includes("/test/data/test.txt"),
    );
    expect(hasInjectedPath).toBe(true);
  });
});

// ── Ward composition ────────────────────────────────────────────────

describe("Ward composition via resolveWards", () => {
  test("multiple max_turns wards resolve to minimum", () => {
    const resolved = resolveWards([max_turns(20), max_turns(50)]);
    expect(resolved.max_turns).toBe(20);
  });

  test("max_turns + require_done compose both constraints", () => {
    const resolved = resolveWards([max_turns(20), require_done()]);
    expect(resolved.max_turns).toBe(20);
    expect(resolved.require_done_tool).toBe(true);
  });

  test("max_depth ward resolves correctly", () => {
    const resolved = resolveWards([max_depth(3)]);
    expect(resolved.max_depth).toBe(3);
  });

  test("empty wards array resolves to defaults", () => {
    const resolved = resolveWards([]);
    expect(resolved.max_turns).toBe(200);
    expect(resolved.require_done_tool).toBe(false);
    expect(resolved.max_depth).toBe(Infinity);
  });

  test("wards with no max_turns use default", () => {
    const resolved = resolveWards([require_done()]);
    expect(resolved.max_turns).toBe(200);
    expect(resolved.require_done_tool).toBe(true);
  });

  test("multiple max_depth wards resolve to minimum", () => {
    const resolved = resolveWards([max_depth(5), max_depth(2)]);
    expect(resolved.max_depth).toBe(2);
  });

  test("all ward types compose together", () => {
    const resolved = resolveWards([max_turns(10), require_done(), max_depth(3)]);
    expect(resolved.max_turns).toBe(10);
    expect(resolved.require_done_tool).toBe(true);
    expect(resolved.max_depth).toBe(3);
  });

  test("exclude_gate composes with other ward types", () => {
    const resolved = resolveWards([max_turns(10), require_done(), exclude_gate("echo")]);
    expect(resolved.max_turns).toBe(10);
    expect(resolved.require_done_tool).toBe(true);
    expect(resolved.exclude_gates).toEqual(["echo"]);
  });

  test("multiple exclude_gate wards compose via union", () => {
    const resolved = resolveWards([exclude_gate("echo"), exclude_gate("read_file")]);
    expect(resolved.exclude_gates.sort()).toEqual(["echo", "read_file"]);
  });
});

// ── Ward-based gate removal in Circle ─────────────────────────────

describe("Ward-based gate removal in Circle", () => {
  test("excluded gate is removed from Circle gates and crystalView", () => {
    const circle = makeCircle(
      [doneGate, echoGate],
      [{ max_turns: 10, require_done_tool: true }, exclude_gate("echo")],
    );

    expect(circle.gates).toHaveLength(1);
    expect(circle.gates[0].name).toBe("done");

    const view = circle.crystalView();
    expect(view.tool_definitions).toHaveLength(1);
    expect(view.tool_definitions[0].name).toBe("done");
  });

  test("excluding nonexistent gate is a no-op", () => {
    const circle = makeCircle(
      [doneGate, echoGate],
      [{ max_turns: 10 }, exclude_gate("nonexistent")],
    );

    expect(circle.gates).toHaveLength(2);
  });

  test("done gate cannot be excluded", () => {
    const circle = makeCircle(
      [doneGate, echoGate],
      [{ max_turns: 10 }, exclude_gate("done")],
    );

    expect(circle.gates.some((g) => g.name === "done")).toBe(true);
  });
});

// ── WARD-1: nested wards compose with min() for numeric, OR for boolean ─

describe("WARD-1: nested ward composition rules", () => {
  test("WARD-1: numeric wards compose with min()", () => {
    // Two different sources of max_turns and max_depth — min() wins
    const resolved = resolveWards([
      { max_turns: 100, max_depth: 5 },
      { max_turns: 50, max_depth: 10 },
    ]);
    expect(resolved.max_turns).toBe(50);  // min(100, 50)
    expect(resolved.max_depth).toBe(5);   // min(5, 10)
  });

  test("WARD-1: boolean wards compose with OR", () => {
    // Only one ward sets require_done_tool — OR means it's true
    const resolved = resolveWards([
      { require_done_tool: false },
      { require_done_tool: true },
    ]);
    expect(resolved.require_done_tool).toBe(true);
  });

  test("WARD-1: three nested ward layers compose correctly", () => {
    // Simulates parent → child → grandchild ward nesting
    const parentWard = { max_turns: 200, max_depth: 10 };
    const childWard = { max_turns: 50, require_done_tool: true };
    const grandchildWard = { max_turns: 100, max_depth: 3 };

    const resolved = resolveWards([parentWard, childWard, grandchildWard]);
    expect(resolved.max_turns).toBe(50);          // min(200, 50, 100)
    expect(resolved.max_depth).toBe(3);            // min(10, 3)
    expect(resolved.require_done_tool).toBe(true); // OR(false, true, false)
  });

  test("WARD-1: nested ward composition with exclude_gates uses union", () => {
    // When multiple ward layers each exclude different gates,
    // the union of all exclusions applies
    const parentWard = { max_turns: 200, exclude_gates: ["echo"] };
    const childWard = { max_turns: 50, exclude_gates: ["read_file"] };
    const grandchildWard = { exclude_gates: ["echo", "write_file"] };

    const resolved = resolveWards([parentWard, childWard, grandchildWard]);
    expect(resolved.max_turns).toBe(50);
    // Union of all exclude_gates across layers
    expect(resolved.exclude_gates.sort()).toEqual(["echo", "read_file", "write_file"]);
  });

  test("WARD-1: nested wards compose all field types together", () => {
    // Full composition: numeric (min), boolean (OR), exclude_gates (union)
    const resolved = resolveWards([
      { max_turns: 100, max_depth: 5, require_done_tool: false, exclude_gates: ["echo"] },
      { max_turns: 50, require_done_tool: true, exclude_gates: ["read_file"] },
      { max_depth: 3, exclude_gates: ["echo"] },
    ]);
    expect(resolved.max_turns).toBe(50);          // min(100, 50)
    expect(resolved.max_depth).toBe(3);            // min(5, 3)
    expect(resolved.require_done_tool).toBe(true); // OR(false, true, false)
    // Union with dedup: ["echo", "read_file"]
    expect(resolved.exclude_gates.sort()).toEqual(["echo", "read_file"]);
  });
});

// ── CIRCLE-11: capability presentation ──────────────────────────────

describe("CIRCLE-11: circle generates capability presentation", () => {
  test("CIRCLE-11: capabilityDocs() returns non-empty docs for gates with docs metadata", () => {
    // BoundGate with docs metadata (docs is set on the BoundGate, not via gate() decorator)
    const documentedGate: BoundGate = {
      name: "read_file",
      definition: {
        name: "read_file",
        description: "Read a file",
        parameters: {
          type: "object",
          properties: { path: { type: "string" } },
          required: ["path"],
          additionalProperties: false,
        },
        strict: true,
      },
      ephemeral: false,
      async execute() { return "content"; },
      docs: {
        section: "File System",
        sandbox_name: "readFile",
        signature: "readFile(path: string): string",
        description: "Read the contents of a file at the given path",
      },
    };

    const circle = makeCircle([doneGate, documentedGate]);
    const docs = circle.capabilityDocs();

    expect(docs.length).toBeGreaterThan(0);
    expect(docs).toContain("File System");
    expect(docs).toContain("readFile");
  });

  test("CIRCLE-11: capabilityDocs() returns empty string when no gates have docs", () => {
    // doneGate has no docs metadata
    const circle = makeCircle([doneGate]);
    const docs = circle.capabilityDocs();
    expect(docs).toBe("");
  });
});
