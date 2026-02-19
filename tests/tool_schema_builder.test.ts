import { describe, expect, test } from "bun:test";

import { GateSchema } from "../src/circle/gate/schema";

describe("tool schema builder", () => {
  test("builds object schema with required and optional fields", () => {
    const schema = GateSchema.create()
      .addString("query")
      .addNumber("limit", { optional: true })
      .addEnum("mode", ["fast", "slow"])
      .build();

    expect(schema).toEqual({
      type: "object",
      properties: {
        query: { type: "string" },
        limit: { type: "number" },
        mode: { type: "string", enum: ["fast", "slow"] },
      },
      required: ["query", "mode"],
      additionalProperties: false,
    });
  });
});
