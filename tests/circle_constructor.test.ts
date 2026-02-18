import { describe, expect, test } from "bun:test";

import { TaskComplete } from "../src/entity/service";
import { tool } from "../src/circle/gate/decorator";
import { Circle } from "../src/circle/circle";
import { max_turns, require_done } from "../src/circle/ward";

// ── Test fixtures ──────────────────────────────────────────────────

const done = tool("Signal task completion", async ({ message }: { message: string }) => {
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

const add = tool("Add two numbers", async ({ a, b }: { a: number; b: number }) => a + b, {
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
  test("returns Ward with given max_turns and require_done_tool false", () => {
    const ward = max_turns(50);
    expect(ward).toEqual({ max_turns: 50, require_done_tool: false });
  });

  test("returns Ward with large value", () => {
    const ward = max_turns(1000);
    expect(ward.max_turns).toBe(1000);
    expect(ward.require_done_tool).toBe(false);
  });
});

describe("require_done helper", () => {
  test("returns Ward with default max_turns of 200", () => {
    const ward = require_done();
    expect(ward).toEqual({ max_turns: 200, require_done_tool: true });
  });

  test("returns Ward with custom max_turns", () => {
    const ward = require_done(50);
    expect(ward).toEqual({ max_turns: 50, require_done_tool: true });
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
    const circle = Circle({ gates: [done], wards: [require_done(50)] });
    expect(circle.wards[0].require_done_tool).toBe(true);
    expect(circle.wards[0].max_turns).toBe(50);
  });

  test("accepts circle with multiple wards", () => {
    const circle = Circle({ gates: [done], wards: [max_turns(100), require_done(50)] });
    expect(circle.wards).toHaveLength(2);
  });
});
