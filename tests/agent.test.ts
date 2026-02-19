import { describe, expect, test } from "bun:test";

import { TaskComplete } from "../src/entity/errors";
import { Entity } from "../src/cantrip/entity";
import { Circle } from "../src/circle/circle";
import { gate } from "../src/circle/gate/decorator";

async function addHandler({ a, b }: { a: number; b: number }) {
  return a + b;
}

const add = gate("Add", addHandler, {
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

const done = gate("Done", doneHandler, {
  name: "done",
  schema: {
    type: "object",
    properties: { message: { type: "string" } },
    required: ["message"],
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
  dependency_overrides?: any;
}) {
  const circle = Circle({
    gates: opts.gates,
    wards: opts.wards ?? [{ max_turns: 200, require_done_tool: false }],
  });
  return new Entity({
    crystal: opts.llm,
    call: {
      system_prompt: opts.system_prompt ?? null,
      hyperparameters: { tool_choice: "auto" },
      gate_definitions: [],
    },
    circle,
    dependency_overrides: opts.dependency_overrides ?? null,
    retry: opts.retry,
  });
}

describe("entity", () => {
  test("executes tool calls and returns content", async () => {
    const llm = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query(messages: any[]) {
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
    const result = await entity.cast("What is 2 + 3?");
    expect(result).toBe("Result is 5");
  });

  test("require_done_tool waits for done", async () => {
    let callCount = 0;
    const llm = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query() {
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

    const result = await entity.cast("finish");
    expect(result).toBe("all set");
  });

  test("retries on retryable errors", async () => {
    let calls = 0;
    const llm = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query() {
        calls += 1;
        if (calls < 3) {
          const err: any = new Error("rate limit");
          err.status_code = 429;
          throw err;
        }
        return { content: "ok", tool_calls: [] };
      },
    };

    const entity = createEntity({
      llm: llm as any,
      gates: [done],
      retry: { max_retries: 3, base_delay: 0, max_delay: 0 },
    });

    const result = await entity.cast("hi");
    expect(result).toBe("ok");
  });

  test("ephemeral tool messages are destroyed", async () => {
    async function ephHandler() {
      return "big output";
    }

    const eph = gate("Ephemeral", ephHandler, {
      name: "ephemeral",
      schema: {
        type: "object",
        properties: {},
        required: [],
        additionalProperties: false,
      },
      ephemeral: 1,
    });

    let step = 0;
    const llm = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query(messages: any[]) {
        step += 1;
        if (step <= 2) {
          return {
            content: null,
            tool_calls: [
              {
                id: `call_${step}`,
                type: "function",
                function: {
                  name: "ephemeral",
                  arguments: "{}",
                },
              },
            ],
          };
        }
        return { content: "done", tool_calls: [] };
      },
    };

    const entity = createEntity({
      llm: llm as any,
      gates: [eph, done],
    });
    const result = await entity.cast("run twice");
    expect(result).toBe("done");

    const toolMessages = entity.history.filter(
      (m) => m.role === "tool",
    ) as any[];
    expect(toolMessages.length).toBe(2);
    expect(toolMessages[0].destroyed).toBe(true);
    expect(toolMessages[1].destroyed).toBe(false);
  });

  test("can disable folding", async () => {
    const llm = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query() {
        return { content: "ok", tool_calls: [] };
      },
    };

    const entity = createEntity({
      llm: llm as any,
      gates: [done],
    });

    const result = await entity.cast("hi");
    expect(result).toBe("ok");
  });
});
