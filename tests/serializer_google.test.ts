import { describe, expect, test } from "bun:test";

import { GoogleMessageSerializer } from "../src/crystal/providers/google/serializer";

const messages = [
  { role: "tool", tool_call_id: "1", tool_name: "t", content: "ok" },
  { role: "tool", tool_call_id: "2", tool_name: "t", content: "ok2" },
  { role: "user", content: "hi" },
];

describe("google serializer", () => {
  test("consecutive tool messages are grouped", () => {
    const { contents } = GoogleMessageSerializer.serializeMessages(messages as any);
    expect(contents.length).toBe(2);
    expect(contents[0].parts.length).toBe(2);
  });
});
