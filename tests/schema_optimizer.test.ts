import { describe, expect, test } from "bun:test";

import { SchemaOptimizer } from "../src/crystal/schema";

describe("SchemaOptimizer", () => {
  test("flattens $ref and enforces additionalProperties false", () => {
    const schema = {
      $defs: {
        Inner: {
          type: "object",
          properties: {
            id: { type: "string" },
          },
          required: ["id"],
        },
      },
      type: "object",
      properties: {
        inner: { $ref: "#/$defs/Inner" },
      },
      required: ["inner"],
    };

    const optimized = SchemaOptimizer.createOptimizedJsonSchema(schema);
    const inner = (optimized.properties as any).inner;
    expect(inner.type).toBe("object");
    expect(inner.additionalProperties).toBe(false);
  });

  test("removes minItems and defaults when configured", () => {
    const schema = {
      type: "object",
      properties: {
        items: {
          type: "array",
          minItems: 1,
          items: { type: "string", default: "x" },
        },
      },
      required: ["items"],
      additionalProperties: false,
    };

    const optimized = SchemaOptimizer.createOptimizedJsonSchema(schema, {
      removeMinItems: true,
      removeDefaults: true,
    });

    const items = (optimized.properties as any).items;
    expect(items.minItems).toBeUndefined();
    expect(items.items.default).toBeUndefined();
  });
});
