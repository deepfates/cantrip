import { describe, expect, test } from "bun:test";

import { ChatGoogle } from "../src/crystal/providers/google/chat";
import type { GateDefinition } from "../src/crystal/crystal";
import { loadEnv } from "./helpers/env";

loadEnv();

const hasKey = Boolean(process.env.GOOGLE_API_KEY);
const it = hasKey ? test : test.skip;

const model = process.env.GOOGLE_MODEL ?? "gemini-2.0-flash";

const echoTool: GateDefinition = {
  name: "echo",
  description: "Echo back the input",
  parameters: {
    type: "object",
    properties: { text: { type: "string" } },
    required: ["text"],
    additionalProperties: false,
  },
  strict: true,
};

describe("integration: google", () => {
  it("returns a response", async () => {
    const llm = new ChatGoogle({ model });
    const response = await llm.ainvoke([
      { role: "user", content: "Reply with 'pong' only." } as any,
    ]);
    expect(response.content?.toLowerCase()).toContain("pong");
  });

  it("returns tool calls when required", async () => {
    const llm = new ChatGoogle({ model });
    const response = await llm.ainvoke(
      [{ role: "user", content: "Call the echo tool with text ping." } as any],
      [echoTool],
      "required"
    );
    expect(response.tool_calls?.length ?? 0).toBeGreaterThan(0);
  });
});
