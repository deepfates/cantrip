import { describe, expect, test, mock, beforeEach, afterEach } from "bun:test";
import { ChatGoogle } from "../../../src/llm/google/chat";

let lastRequestBody: any = null;
let lastRequestHeaders: Record<string, string> = {};
const originalFetch = globalThis.fetch;

beforeEach(() => {
  globalThis.fetch = mock(async (url: string, init: any) => {
    lastRequestBody = JSON.parse(init.body);
    lastRequestHeaders = init.headers;

    if (url.includes("cachedContents")) {
      return new Response(JSON.stringify({ error: { message: "not found" } }), { status: 404 });
    }

    return new Response(
      JSON.stringify({
        candidates: [{ content: { parts: [{ text: "ok" }] }, finishReason: "STOP" }],
        usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 5, totalTokenCount: 15 },
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

describe("ChatGoogle request shaping", () => {
  test("does not retry on 429", async () => {
    let fetchCount = 0;
    globalThis.fetch = mock(async () => {
      fetchCount++;
      return new Response(JSON.stringify({ error: { message: "rate limited" } }), { status: 429 });
    }) as any;

    const llm = new ChatGoogle({ model: "gemini-2.0-flash", api_key: "test-key" });
    await expect(llm.query([{ role: "user", content: "hi" } as any])).rejects.toThrow();
    expect(fetchCount).toBe(1);
  });

  test("temperature not sent when not specified", async () => {
    const llm = new ChatGoogle({
      model: "gemini-2.0-flash",
      api_key: "test-key",
      explicit_context_caching: false,
    });
    await llm.query([{ role: "user", content: "hi" } as any]);
    expect(lastRequestBody.generationConfig).not.toHaveProperty("temperature");
  });

  test("maxOutputTokens not sent when not specified", async () => {
    const llm = new ChatGoogle({
      model: "gemini-2.0-flash",
      api_key: "test-key",
      explicit_context_caching: false,
    });
    await llm.query([{ role: "user", content: "hi" } as any]);
    expect(lastRequestBody.generationConfig).not.toHaveProperty("maxOutputTokens");
  });

  test("explicit_context_caching defaults to false", () => {
    const llm = new ChatGoogle({ model: "gemini-2.0-flash", api_key: "test-key" });
    expect(llm.explicit_context_caching).toBe(false);
  });

  test("no thinkingConfig when thinking_budget not set, even for gemini-2.5-flash", async () => {
    const llm = new ChatGoogle({
      model: "gemini-2.5-flash",
      api_key: "test-key",
      explicit_context_caching: false,
    });
    await llm.query([{ role: "user", content: "hi" } as any]);
    expect(lastRequestBody.generationConfig).not.toHaveProperty("thinkingConfig");
  });
});
