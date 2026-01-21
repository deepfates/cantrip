import { describe, expect, test } from "bun:test";

import { tool } from "../src/tools/decorator";

describe("tool schema inference", () => {
  test("builds schema from params map", () => {
    const t = tool(
      "Test",
      async (_: any) => "ok",
      {
        name: "test",
        params: {
          a: "string",
          b: "number",
          c: "boolean?",
          tags: "string[]",
          meta: "object",
        },
      } as any
    );

    expect(t.definition.parameters).toEqual({
      type: "object",
      properties: {
        a: { type: "string" },
        b: { type: "number" },
        c: { type: "boolean" },
        tags: { type: "array", items: { type: "string" } },
        meta: { type: "object", additionalProperties: false },
      },
      required: ["a", "b", "tags", "meta"],
      additionalProperties: false,
    });
  });
});
