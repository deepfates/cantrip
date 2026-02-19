import { describe, expect, test } from "bun:test";

import { Entity } from "../src/cantrip/entity";
import { Circle } from "../src/circle/circle";
import { rawGate } from "../src/circle/gate/raw";
import { TaskComplete } from "../src/entity/errors";

const add = rawGate(
  {
    name: "add",
    description: "Add",
    parameters: {
      type: "object",
      properties: { a: { type: "integer" }, b: { type: "integer" } },
      required: ["a", "b"],
      additionalProperties: false,
    },
  },
  async ({ a, b }: { a: number; b: number }) => a + b,
);

const done = rawGate(
  {
    name: "done",
    description: "Done",
    parameters: {
      type: "object",
      properties: { message: { type: "string" } },
      required: ["message"],
      additionalProperties: false,
    },
  },
  async ({ message }: { message: string }) => {
    throw new TaskComplete(message);
  },
);

/** Helper to create an Entity with minimal boilerplate. */
function createEntity(opts: {
  llm: any;
  gates: any[];
  wards?: any[];
}) {
  const circle = Circle({
    gates: opts.gates,
    wards: opts.wards ?? [{ max_turns: 200, require_done_tool: false }],
  });
  return new Entity({
    crystal: opts.llm,
    call: {
      system_prompt: null,
      hyperparameters: { tool_choice: "auto" },
      gate_definitions: [],
    },
    circle,
    dependency_overrides: null,
  });
}

describe("entity (from core agent tests)", () => {
  test("executes tool calls and returns content", async () => {
    const llm = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke(messages: any[]) {
        if (messages.filter((m: any) => m.role === "tool").length === 0) {
          return {
            content: null,
            tool_calls: [
              {
                id: "call_1",
                type: "function",
                function: {
                  name: "add",
                  arguments: JSON.stringify({ a: 2, b: 3 }),
                },
              },
            ],
          };
        }
        return { content: "Result is 5", tool_calls: [] };
      },
    };

    const entity = createEntity({
      llm: llm as any,
      gates: [add, done],
    });
    const result = await entity.turn("What is 2 + 3?");
    expect(result).toBe("Result is 5");
  });

  test("require_done_tool waits for done", async () => {
    let callCount = 0;
    const llm = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke() {
        callCount += 1;
        if (callCount === 1) {
          return {
            content: null,
            tool_calls: [
              {
                id: "call_1",
                type: "function",
                function: {
                  name: "done",
                  arguments: JSON.stringify({ message: "all set" }),
                },
              },
            ],
          };
        }
        return { content: "Should not get here", tool_calls: [] };
      },
    };

    const entity = createEntity({
      llm: llm as any,
      gates: [done],
      wards: [{ max_turns: 200, require_done_tool: true }],
    });

    const result = await entity.turn("finish");
    expect(result).toBe("all set");
  });

  test("propagates non-retryable errors", async () => {
    const llm = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke() {
        throw new Error("boom");
      },
    };

    const entity = createEntity({
      llm: llm as any,
      gates: [done],
    });
    await expect(entity.turn("hi")).rejects.toThrow("boom");
  });
});
