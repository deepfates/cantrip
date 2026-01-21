import { describe, expect, test } from "bun:test";

import { ChatAnthropic } from "../src/llm/anthropic/chat";
import type { ToolDefinition } from "../src/llm/base";
import { loadEnv } from "./helpers/env";

loadEnv();

const hasKey = Boolean(process.env.ANTHROPIC_API_KEY);
const it = hasKey ? test : test.skip;

const model = process.env.ANTHROPIC_MODEL ?? "claude-3-5-sonnet-20240620";

const echoTool: ToolDefinition = {
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

describe("integration: anthropic", () => {
  it("returns a response", async () => {
    const llm = new ChatAnthropic({ model });
    const response = await llm.ainvoke([
      { role: "user", content: "Reply with 'pong' only." } as any,
    ]);
    expect(response.content?.toLowerCase()).toContain("pong");
  });

  it("returns tool calls when required", async () => {
    const llm = new ChatAnthropic({ model });
    const response = await llm.ainvoke(
      [{ role: "user", content: "Call the echo tool with text ping." } as any],
      [echoTool],
      "required"
    );
    expect(response.tool_calls?.length ?? 0).toBeGreaterThan(0);
  });
});
