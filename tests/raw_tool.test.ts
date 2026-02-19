import { describe, expect, test } from "bun:test";

import { rawTool } from "../src/circle/gate/raw";

describe("raw tool", () => {
  test("exposes definition and executes handler", async () => {
    const tool = rawTool(
      {
        name: "echo",
        description: "Echo",
        parameters: {
          type: "object",
          properties: { text: { type: "string" } },
          required: ["text"],
          additionalProperties: false,
        },
      },
      async ({ text }: { text: string }) => `hi ${text}`,
    );

    expect(tool.definition.name).toBe("echo");
    expect(tool.definition.description).toBe("Echo");
    expect(tool.definition.parameters).toHaveProperty("type", "object");

    const result = await tool.execute({ text: "there" });
    expect(result).toBe("hi there");
  });
});
