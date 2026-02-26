import { describe, expect, test } from "bun:test";

import { AnthropicMessageSerializer } from "../src/llm/anthropic/serializer";

const messages = [
  { role: "user", content: "hi", cache: true },
  { role: "assistant", content: "there", cache: true },
];

describe("anthropic serializer", () => {
  test("only last cached message remains cached", () => {
    const { messages: serialized } = AnthropicMessageSerializer.serializeMessages(
      messages as any
    );

    const userContent = serialized[0].content;
    const assistantContent = serialized[1].content;

    // First message should not carry cache_control anymore
    if (Array.isArray(userContent)) {
      const block = userContent[0];
      expect(block.cache_control).toBeUndefined();
    }

    // Last cached message should carry cache_control
    if (Array.isArray(assistantContent)) {
      const last = assistantContent[assistantContent.length - 1];
      expect(last.cache_control).toBeDefined();
    }
  });
});
