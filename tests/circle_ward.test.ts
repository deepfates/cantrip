import { describe, expect, test } from "bun:test";

import { TaskComplete } from "../src/entity/errors";
import { Entity } from "../src/cantrip/entity";
import { Circle } from "../src/circle/circle";
import { gate } from "../src/circle/gate/decorator";
import { renderGateDefinitions } from "../src/cantrip/call";
import { DEFAULT_WARD, resolveWards } from "../src/circle/ward";
import type { Ward } from "../src/circle/ward";
import type { Call } from "../src/cantrip/call";

// ── Test fixtures ──────────────────────────────────────────────────

async function addHandler({ a, b }: { a: number; b: number }) {
  return a + b;
}

const add = gate("Add two numbers", addHandler, {
  name: "add",
  schema: {
    type: "object",
    properties: { a: { type: "integer" }, b: { type: "integer" } },
    required: ["a", "b"],
    additionalProperties: false,
  },
});

async function doneHandler({ message }: { message: string }) {
  throw new TaskComplete(message);
}

const done = gate("Mark task as done", doneHandler, {
  name: "done",
  schema: {
    type: "object",
    properties: { message: { type: "string" } },
    required: ["message"],
    additionalProperties: false,
  },
});

const dummyLlm = {
  model: "dummy",
  provider: "dummy",
  name: "dummy",
  async ainvoke() {
    return { content: "ok", tool_calls: [] };
  },
};

// ── renderGateDefinitions ──────────────────────────────────────────

describe("renderGateDefinitions", () => {
  test("extracts GateDefinition from GateResult[]", () => {
    const rendered = renderGateDefinitions([add, done]);
    expect(rendered).toHaveLength(2);
    expect(rendered[0].name).toBe("add");
    expect(rendered[0].description).toBe("Add two numbers");
    expect(rendered[0].parameters).toEqual({
      type: "object",
      properties: { a: { type: "integer" }, b: { type: "integer" } },
      required: ["a", "b"],
      additionalProperties: false,
    });
    expect(rendered[1].name).toBe("done");
    expect(rendered[1].description).toBe("Mark task as done");
  });

  test("returns empty array for no gates", () => {
    expect(renderGateDefinitions([])).toEqual([]);
  });

  test("rendered definitions have no execute function", () => {
    const rendered = renderGateDefinitions([add]);
    // GateDefinition should only have name, description, parameters, strict?
    expect(rendered[0]).not.toHaveProperty("execute");
    expect(rendered[0]).not.toHaveProperty("ephemeral");
  });
});

// ── Call type ──────────────────────────────────────────────────────

describe("Call type", () => {
  test("Call.gate_definitions accepts rendered definitions", () => {
    const call: Call = {
      system_prompt: "You are helpful",
      hyperparameters: { tool_choice: "auto" },
      gate_definitions: renderGateDefinitions([add]),
    };
    expect(call.gate_definitions[0].name).toBe("add");
    expect(call.gate_definitions[0]).not.toHaveProperty("execute");
  });
});

// ── Ward defaults ──────────────────────────────────────────────────

describe("Ward", () => {
  test("DEFAULT_WARD has expected values", () => {
    expect(DEFAULT_WARD.max_turns).toBe(200);
    expect(DEFAULT_WARD.require_done_tool).toBe(false);
  });

  test("Ward type is structurally correct", () => {
    const ward: Ward = { max_turns: 10, require_done_tool: true };
    expect(ward.max_turns).toBe(10);
    expect(ward.require_done_tool).toBe(true);
  });
});

// ── Circle wiring into Entity ────────────────────────────────────

describe("Entity with Circle", () => {
  test("Circle gates are accessible on the circle", () => {
    const circle = Circle({
      gates: [add, done],
      wards: [{ max_turns: 50, require_done_tool: true }],
    });

    expect(circle.gates).toHaveLength(2);
    expect(circle.gates[0].name).toBe("add");
    expect(circle.gates[1].name).toBe("done");
  });

  test("Circle wards are resolved correctly", () => {
    const circle = Circle({
      gates: [add, done],
      wards: [{ max_turns: 42, require_done_tool: true }],
    });

    const resolved = resolveWards(circle.wards);
    expect(resolved.max_turns).toBe(42);
    expect(resolved.require_done_tool).toBe(true);
  });

  test("Entity with Circle can turn", async () => {
    const circle = Circle({
      gates: [add, done],
      wards: [{ max_turns: 10, require_done_tool: false }],
    });

    const entity = new Entity({
      crystal: dummyLlm as any,
      call: {
        system_prompt: null,
        hyperparameters: { tool_choice: "auto" },
        gate_definitions: [],
      },
      circle,
      dependency_overrides: null,
    });
    const result = await entity.turn("hello");
    expect(result).toBe("ok");
  });
});
