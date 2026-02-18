import { describe, expect, test } from "bun:test";

import { Agent, TaskComplete } from "../src/entity/service";
import { tool } from "../src/circle/gate/decorator";
import { renderGateDefinitions } from "../src/cantrip/call";
import type { Circle } from "../src/circle/circle";
import { DEFAULT_WARD } from "../src/circle/ward";
import type { Ward } from "../src/circle/ward";
import type { Call } from "../src/cantrip/call";

// ── Test fixtures ──────────────────────────────────────────────────

async function addHandler({ a, b }: { a: number; b: number }) {
  return a + b;
}

const add = tool("Add two numbers", addHandler, {
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

const done = tool("Mark task as done", doneHandler, {
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

// ── Circle wiring into Agent ───────────────────────────────────────

describe("Agent with Circle", () => {
  test("accepts Circle and derives tools from gates", () => {
    const circle: Circle = {
      gates: [add, done],
      wards: [{ max_turns: 50, require_done_tool: true }],
    };

    const agent = new Agent({ llm: dummyLlm as any, circle });
    // Agent should have the tools from the circle
    expect(agent.tools).toHaveLength(2);
    expect(agent.tools[0].name).toBe("add");
    expect(agent.tools[1].name).toBe("done");
  });

  test("Circle ward overrides max_iterations", () => {
    const circle: Circle = {
      gates: [add],
      wards: [{ max_turns: 42, require_done_tool: false }],
    };

    const agent = new Agent({ llm: dummyLlm as any, circle });
    expect(agent.max_iterations).toBe(42);
  });

  test("Circle ward overrides require_done_tool", () => {
    const circle: Circle = {
      gates: [add],
      wards: [{ max_turns: 100, require_done_tool: true }],
    };

    const agent = new Agent({ llm: dummyLlm as any, circle });
    expect(agent.require_done_tool).toBe(true);
  });

  test("explicit options take precedence over Circle ward", () => {
    const circle: Circle = {
      gates: [add],
      wards: [{ max_turns: 42, require_done_tool: true }],
    };

    const agent = new Agent({
      llm: dummyLlm as any,
      circle,
      max_iterations: 10,
      require_done_tool: false,
    });
    // Explicit options win
    expect(agent.max_iterations).toBe(10);
    expect(agent.require_done_tool).toBe(false);
  });

  test("explicit tools take precedence over Circle gates", () => {
    const circle: Circle = {
      gates: [add, done],
      wards: [DEFAULT_WARD],
    };

    const agent = new Agent({
      llm: dummyLlm as any,
      tools: [add],
      circle,
    });
    // Explicit tools wins
    expect(agent.tools).toHaveLength(1);
    expect(agent.tools[0].name).toBe("add");
  });

  test("backward compatible: Agent without circle still works", () => {
    const agent = new Agent({
      llm: dummyLlm as any,
      tools: [add],
      max_iterations: 5,
      require_done_tool: true,
    });
    expect(agent.tools).toHaveLength(1);
    expect(agent.max_iterations).toBe(5);
    expect(agent.require_done_tool).toBe(true);
  });

  test("Circle with no wards uses DEFAULT_WARD", () => {
    const circle: Circle = {
      gates: [add],
      wards: [],
    };

    const agent = new Agent({ llm: dummyLlm as any, circle });
    expect(agent.max_iterations).toBe(DEFAULT_WARD.max_turns);
    expect(agent.require_done_tool).toBe(DEFAULT_WARD.require_done_tool);
  });

  test("Agent with Circle can query", async () => {
    const circle: Circle = {
      gates: [add],
      wards: [{ max_turns: 10, require_done_tool: false }],
    };

    const agent = new Agent({ llm: dummyLlm as any, circle });
    const result = await agent.query("hello");
    expect(result).toBe("ok");
  });
});
