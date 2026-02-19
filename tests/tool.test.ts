import { describe, expect, test } from "bun:test";

import { gate, serializeGateResult } from "../src/circle/gate/decorator";
import { Depends } from "../src/circle/gate/depends";

function getValue() {
  return 42;
}

async function addHandler({ a, b }: { a: number; b: number }) {
  return a + b;
}

const add = gate("Add two numbers", addHandler, {
  name: "add",
  schema: {
    type: "object",
    properties: {
      a: { type: "integer" },
      b: { type: "integer" },
    },
    required: ["a", "b"],
    additionalProperties: false,
  },
});

async function depsHandler(_: {}, deps: any) {
  return deps.value;
}

const withDeps = gate("Return dep value", depsHandler, {
  name: "with_deps",
  schema: {
    type: "object",
    properties: {},
    required: [],
    additionalProperties: false,
  },
  dependencies: { value: new Depends(getValue) },
});

describe("tools", () => {
  test("tool definitions expose schema", () => {
    const def = add.definition;
    expect(def.name).toBe("add");
    expect(def.parameters).toEqual({
      type: "object",
      properties: { a: { type: "integer" }, b: { type: "integer" } },
      required: ["a", "b"],
      additionalProperties: false,
    });
  });

  test("throws error when arrow function has no explicit name", () => {
    expect(() => {
      gate("Anonymous tool", async () => "result", {
        schema: {
          type: "object",
          properties: {},
          required: [],
          additionalProperties: false,
        },
      });
    }).toThrow("Gate name is required");
  });

  test("uses handler.name for named functions", () => {
    async function myNamedTool() {
      return "result";
    }
    const t = gate("A named tool", myNamedTool, {
      schema: {
        type: "object",
        properties: {},
        required: [],
        additionalProperties: false,
      },
    });
    expect(t.name).toBe("myNamedTool");
  });

  test("tool executes with dependencies", async () => {
    const result = await withDeps.execute({});
    expect(result).toBe("42");
  });

  test("serializeGateResult handles objects", () => {
    const result = serializeGateResult({ ok: true });
    expect(result).toBe('{"ok":true}');
  });

  test("serializeGateResult handles text parts", () => {
    const result = serializeGateResult([{ type: "text", text: "hi" }]);
    expect(result).toEqual([{ type: "text", text: "hi" }]);
  });
});
