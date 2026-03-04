import { describe, expect, test } from "bun:test";

import { ChatLMStudio } from "../../src/llm/lmstudio/chat";
import type { GateDefinition } from "../../src/llm/base";
import { loadEnv } from "../helpers/env";

loadEnv();

const model = process.env.LM_STUDIO_MODEL ?? "gpt-oss-20b";
const base_url = process.env.LM_STUDIO_BASE_URL ?? "http://localhost:1234/v1";

// Probe the local server — skip if it's not running
let serverAvailable = false;
try {
  const res = await fetch(`${base_url}/models`, { signal: AbortSignal.timeout(2000) });
  serverAvailable = res.ok;
} catch {}

const it = serverAvailable ? test : test.skip;

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
