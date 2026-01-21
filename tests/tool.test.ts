import { describe, expect, test } from "bun:test";

import { tool, serializeToolResult } from "../src/tools/decorator";
import { Depends } from "../src/tools/depends";

function getValue() {
  return 42;
}

async function addHandler({ a, b }: { a: number; b: number }) {
  return a + b;
}

const add = tool("Add two numbers", addHandler, {
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

const withDeps = tool("Return dep value", depsHandler, {
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

  test("tool executes with dependencies", async () => {
    const result = await withDeps.execute({});
    expect(result).toBe("42");
  });

  test("serializeToolResult handles objects", () => {
    const result = serializeToolResult({ ok: true });
    expect(result).toBe('{"ok":true}');
  });

  test("serializeToolResult handles text parts", () => {
    const result = serializeToolResult([{ type: "text", text: "hi" }]);
    expect(result).toEqual([{ type: "text", text: "hi" }]);
  });
});
