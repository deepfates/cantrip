import { describe, expect, test } from "bun:test";

import { TaskComplete } from "../src/entity/service";
import { gate } from "../src/circle/gate/decorator";
import { Circle } from "../src/circle/circle";
import { done_for_medium } from "../src/circle/gate/builtin/done";
import { js } from "../src/circle/medium/js";
import { max_turns, require_done, max_depth, resolveWards } from "../src/circle/ward";

// ── Test fixtures ──────────────────────────────────────────────────

const done = gate("Signal task completion", async ({ message }: { message: string }) => {
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

const add = gate("Add two numbers", async ({ a, b }: { a: number; b: number }) => a + b, {
  name: "add",
  schema: {
    type: "object",
    properties: { a: { type: "integer" }, b: { type: "integer" } },
    required: ["a", "b"],
    additionalProperties: false,
  },
});

// ── Ward helpers ──────────────────────────────────────────────────

describe("max_turns helper", () => {
  test("returns Ward with only max_turns set", () => {
    const ward = max_turns(50);
    expect(ward).toEqual({ max_turns: 50 });
  });

  test("returns Ward with large value", () => {
    const ward = max_turns(1000);
    expect(ward.max_turns).toBe(1000);
  });
});

describe("require_done helper", () => {
  test("returns Ward with only require_done_tool set", () => {
    const ward = require_done();
    expect(ward).toEqual({ require_done_tool: true });
  });
});

describe("max_depth helper", () => {
  test("returns Ward with only max_depth set", () => {
    const ward = max_depth(3);
    expect(ward).toEqual({ max_depth: 3 });
  });
});

// ── Circle() constructor ──────────────────────────────────────────

describe("Circle() constructor", () => {
  test("constructs valid circle with done gate and ward", () => {
    const circle = Circle({ gates: [done, add], wards: [max_turns(100)] });
    expect(circle.gates).toHaveLength(2);
    expect(circle.wards).toHaveLength(1);
    expect(circle.wards[0].max_turns).toBe(100);
  });

  test("throws when no done gate present (CIRCLE-1)", () => {
    expect(() => {
      Circle({ gates: [add], wards: [max_turns(100)] });
    }).toThrow("Circle must have a done gate");
  });

  test("throws when gates array is empty (CIRCLE-1)", () => {
    expect(() => {
      Circle({ gates: [], wards: [max_turns(100)] });
    }).toThrow("Circle must have a done gate");
  });

  test("throws when wards array is empty (CIRCLE-2)", () => {
    expect(() => {
      Circle({ gates: [done], wards: [] });
    }).toThrow("Circle must have at least one ward");
  });

  test("accepts circle with require_done ward", () => {
    const circle = Circle({ gates: [done], wards: [require_done(), max_turns(50)] });
    expect(circle.wards[0].require_done_tool).toBe(true);
    expect(circle.wards[1].max_turns).toBe(50);
  });

  test("accepts circle with multiple wards", () => {
    const circle = Circle({ gates: [done], wards: [max_turns(100), require_done()] });
    expect(circle.wards).toHaveLength(2);
  });
});

// ── Circle() with medium: auto-inject done_for_medium ────────────

describe("Circle() with medium auto-injects done_for_medium", () => {
  test("auto-injects done gate when medium present and no gates provided", async () => {
    const circle = Circle({ medium: js(), wards: [max_turns(10)] });
    expect(circle.gates).toHaveLength(1);
    expect(circle.gates[0].name).toBe("done");
    if (circle.dispose) await circle.dispose();
  });

  test("auto-injects done gate when medium present and gates has no done", async () => {
    const myGate = gate("noop", async () => "ok", {
      name: "my_gate",
      schema: { type: "object", properties: {}, additionalProperties: false },
    });
    const circle = Circle({ medium: js(), gates: [myGate], wards: [max_turns(10)] });
    expect(circle.gates).toHaveLength(2);
    expect(circle.gates.some((g) => g.name === "done")).toBe(true);
    expect(circle.gates.some((g) => g.name === "my_gate")).toBe(true);
    if (circle.dispose) await circle.dispose();
  });

  test("does not duplicate done gate when explicitly provided", async () => {
    const circle = Circle({
      medium: js(),
      gates: [done_for_medium()],
      wards: [max_turns(10)],
    });
    const doneGates = circle.gates.filter((g) => g.name === "done");
    expect(doneGates).toHaveLength(1);
    if (circle.dispose) await circle.dispose();
  });
});
