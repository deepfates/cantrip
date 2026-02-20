import { describe, expect, test } from "bun:test";

import { gate } from "../../../src/circle/gate/decorator";

describe("zod schema inference", () => {
  test("infers schema from zod object", async () => {
    let z: any;
    try {
      const mod = await import("zod");
      z = mod.z;
    } catch {
      return;
    }

    const schema = z.object({
      name: z.string(),
      count: z.number().optional(),
      tags: z.array(z.string()),
    });

    const t = gate("Zod", async (_: any) => "ok", {
      name: "zod",
      zodSchema: schema,
    } as any);

    expect(t.definition.parameters).toEqual({
      type: "object",
      properties: {
        name: { type: "string" },
        count: { type: "number" },
        tags: { type: "array", items: { type: "string" } },
      },
      required: ["name", "tags"],
      additionalProperties: false,
    });
  });
});
