import { describe, expect, test } from "bun:test";

import { ChatLMStudio } from "../../src/crystal/providers/lmstudio/chat";
import type { GateDefinition } from "../../src/crystal/crystal";
import { loadEnv } from "../helpers/env";

loadEnv();

const runLive =
  process.env.LM_STUDIO_TEST === "1" || process.env.LM_STUDIO_TEST === "true";

const it = runLive ? test : test.skip;

const model = process.env.LM_STUDIO_MODEL ?? "gpt-oss-20b";
const base_url = process.env.LM_STUDIO_BASE_URL ?? "http://localhost:1234/v1";

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

describe("integration: lmstudio (local server)", () => {
  it("returns a response from local LM Studio", async () => {
    const llm = new ChatLMStudio({ model, base_url });
    const response = await llm.query([
      { role: "user", content: "Reply with 'pong' only." } as any,
    ]);
    expect(response.content?.toLowerCase()).toContain("pong");
  });

  it("returns tool calls when required", async () => {
    const llm = new ChatLMStudio({ model, base_url });
    const response = await llm.query(
      [{ role: "user", content: "Call the echo tool with text ping." } as any],
      [echoTool],
      "required",
    );
    expect(response.tool_calls?.length ?? 0).toBeGreaterThan(0);
  });
});
