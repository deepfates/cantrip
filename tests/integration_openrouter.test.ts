import { describe, expect, test } from "bun:test";

import { ChatOpenRouter } from "../src/crystal/providers/openrouter/chat";
import type { GateDefinition } from "../src/crystal/crystal";
import { loadEnv } from "./helpers/env";

loadEnv();

const hasKey = Boolean(process.env.OPENROUTER_API_KEY);
const it = hasKey ? test : test.skip;

// OpenRouter model names are provider-qualified; default to OpenAI's current frontier.
const model = process.env.OPENROUTER_MODEL ?? "openai/gpt-5.1";

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

describe("integration: openrouter", () => {
  it("returns a response", async () => {
    const llm = new ChatOpenRouter({ model });
    const response = await llm.query([
      { role: "user", content: "Reply with 'pong' only." } as any,
    ]);
    expect(response.content?.toLowerCase()).toContain("pong");
  });

  it("returns tool calls when required", async () => {
    const llm = new ChatOpenRouter({ model });
    const response = await llm.query(
      [{ role: "user", content: "Call the echo tool with text ping." } as any],
      [echoTool],
      "required",
    );
    expect(response.tool_calls?.length ?? 0).toBeGreaterThan(0);
  });
});
