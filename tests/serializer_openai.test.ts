import { describe, expect, test } from "bun:test";

import { OpenAIMessageSerializer } from "../src/llm/openai/serializer";

const toolMessage = {
  role: "tool",
  tool_call_id: "call_1",
  tool_name: "foo",
  content: "result",
  destroyed: false,
};

const destroyedToolMessage = {
  role: "tool",
  tool_call_id: "call_2",
  tool_name: "foo",
  content: "result",
  destroyed: true,
};

describe("openai serializer", () => {
  test("tool message serialized as tool role", () => {
    const out = OpenAIMessageSerializer.serialize(toolMessage as any);
    expect(out.role).toBe("tool");
    expect(out.content).toBe("result");
  });

  test("destroyed tool message uses placeholder", () => {
    const out = OpenAIMessageSerializer.serialize(destroyedToolMessage as any);
    expect(out.content).toBe("<removed to save context>");
  });
});
