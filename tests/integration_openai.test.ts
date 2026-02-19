import { describe, expect, test } from "bun:test";

import { ChatOpenAI } from "../src/crystal/providers/openai/chat";
import type { GateDefinition } from "../src/crystal/crystal";
import { loadEnv } from "./helpers/env";

loadEnv();

const hasKey = Boolean(process.env.OPENAI_API_KEY);
const it = hasKey ? test : test.skip;

const model = process.env.OPENAI_MODEL ?? "gpt-5-mini";

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

describe("integration: openai", () => {
  it("returns a response", async () => {
    const llm = new ChatOpenAI({ model });
    const response = await llm.query([
      { role: "user", content: "Reply with 'pong' only." } as any,
    ]);
    expect(response.content?.toLowerCase()).toContain("pong");
  });

  it("returns tool calls when required", async () => {
    const llm = new ChatOpenAI({ model });
    const response = await llm.query(
      [{ role: "user", content: "Call the echo tool with text ping." } as any],
      [echoTool],
      "required",
    );
    expect(response.tool_calls?.length ?? 0).toBeGreaterThan(0);
  });
});
