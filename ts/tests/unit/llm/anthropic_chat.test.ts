import { describe, expect, test, mock, beforeEach, afterEach } from "bun:test";
import { ChatAnthropic } from "../../../src/llm/anthropic/chat";

let lastRequestBody: any = null;
let lastRequestHeaders: Record<string, string> = {};
const originalFetch = globalThis.fetch;

beforeEach(() => {
  globalThis.fetch = mock(async (_url: string, init: any) => {
    lastRequestBody = JSON.parse(init.body);
    lastRequestHeaders = init.headers;
    return new Response(
      JSON.stringify({
        content: [{ type: "text", text: "ok" }],
        usage: { input_tokens: 10, output_tokens: 5 },
        stop_reason: "end_turn",
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }) as any;
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  lastRequestBody = null;
  lastRequestHeaders = {};
});

describe("ChatAnthropic defaults", () => {
  test("no anthropic-beta header when prompt_cache_beta not set", async () => {
    const llm = new ChatAnthropic({ model: "claude-sonnet-4-5", api_key: "test-key" });
    await llm.query([{ role: "user", content: "hi" } as any]);
    expect(lastRequestHeaders).not.toHaveProperty("anthropic-beta");
  });

  test("no cache_control on tools by default", async () => {
    const llm = new ChatAnthropic({ model: "claude-sonnet-4-5", api_key: "test-key" });
    const tools = Array.from({ length: 5 }, (_, i) => ({
      name: `tool_${i}`,
      description: `Tool ${i}`,
      parameters: { type: "object", properties: {}, required: [] },
    }));
    await llm.query([{ role: "user", content: "hi" } as any], tools, "auto");
    for (const tool of lastRequestBody.tools) {
      expect(tool).not.toHaveProperty("cache_control");
    }
  });
});
