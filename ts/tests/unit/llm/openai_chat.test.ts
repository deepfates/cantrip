import { describe, expect, test, mock, beforeEach, afterEach } from "bun:test";
import { ChatOpenAI } from "../../../src/llm/openai/chat";

let lastRequestBody: any = null;
let lastRequestHeaders: Record<string, string> = {};
const originalFetch = globalThis.fetch;

const echoTool = {
  name: "echo",
  description: "Echo back",
  parameters: {
    type: "object",
    properties: { text: { type: "string" } },
    required: ["text"],
  },
  strict: true,
};

beforeEach(() => {
  globalThis.fetch = mock(async (_url: string, init: any) => {
    lastRequestBody = JSON.parse(init.body);
    lastRequestHeaders = init.headers;
    return new Response(
      JSON.stringify({
        choices: [{ message: { content: "ok", tool_calls: null }, finish_reason: "stop" }],
        usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
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

describe("ChatOpenAI request shaping", () => {
  test("reasoning mode does not send parallel_tool_calls", async () => {
    const llm = new ChatOpenAI({
      model: "o3",
      reasoning: true,
      reasoning_effort: "low",
      require_api_key: false,
    });
    await llm.query([{ role: "user", content: "hi" } as any], [echoTool], "auto");
    expect(lastRequestBody).not.toHaveProperty("parallel_tool_calls");
  });

  test("reasoning mode does not send top_p", async () => {
    const llm = new ChatOpenAI({
      model: "o3",
      reasoning: true,
      top_p: 0.9,
      require_api_key: false,
    });
    await llm.query([{ role: "user", content: "hi" } as any]);
    expect(lastRequestBody).not.toHaveProperty("top_p");
  });

  test("makeStrictSchema handles optional property with no type field", () => {
    const llm = new ChatOpenAI({ model: "test", require_api_key: false });
    const schema = {
      type: "object",
      properties: { x: { enum: ["a", "b"] } },
      required: [],
    };
    const result = (llm as any).makeStrictSchema(schema);
    const json = JSON.stringify(result);
    expect(json).toBeTruthy();
    const xProp = result.properties.x;
    expect(xProp.anyOf || (Array.isArray(xProp.type) && xProp.type.includes("null"))).toBeTruthy();
  });

  test("tool strict defaults to false when not specified", async () => {
    const llm = new ChatOpenAI({ model: "gpt-5", require_api_key: false });
    const tool = {
      name: "echo",
      description: "Echo",
      parameters: {
        type: "object",
        properties: { text: { type: "string" } },
        required: ["text"],
      },
    };
    await llm.query([{ role: "user", content: "hi" } as any], [tool], "auto");
    expect(lastRequestBody.tools[0].function.strict).toBe(false);
  });

  test("max_completion_tokens not sent when not specified", async () => {
    const llm = new ChatOpenAI({ model: "gpt-5", require_api_key: false });
    await llm.query([{ role: "user", content: "hi" } as any]);
    expect(lastRequestBody).not.toHaveProperty("max_completion_tokens");
  });

  test("no extra_body or prompt_cache fields in request", async () => {
    const llm = new ChatOpenAI({ model: "gpt-5", require_api_key: false });
    await llm.query([{ role: "user", content: "hi" } as any]);
    expect(lastRequestBody).not.toHaveProperty("extra_body");
    expect(lastRequestBody).not.toHaveProperty("prompt_cache_key");
    expect(lastRequestBody).not.toHaveProperty("prompt_cache_retention");
  });
});
