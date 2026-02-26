import { describe, expect, test } from "bun:test";

import { ChatAnthropic } from "../../../src/crystal/providers/anthropic/chat";
import { ChatOpenAI } from "../../../src/crystal/providers/openai/chat";

// Access private getToolChoice via prototype trick
function getAnthropicToolChoice(
  toolChoice: any,
  tools: any[] | null = [{ name: "js" }]
): any {
  const instance = new ChatAnthropic({ model: "claude-sonnet-4-20250514" });
  return (instance as any).getToolChoice(toolChoice, tools);
}

function getOpenAIToolChoice(
  toolChoice: any,
  tools: any[] | null = [{ name: "js" }]
): any {
  const instance = new ChatOpenAI({ model: "gpt-4o", require_api_key: false });
  return (instance as any).getToolChoice(toolChoice, tools);
}

// ── Anthropic provider ───────────────────────────────────────────────

describe("ChatAnthropic.getToolChoice", () => {
  test("returns null when tool_choice is null", () => {
    expect(getAnthropicToolChoice(null)).toBeNull();
  });

  test("returns null when tools is null", () => {
    expect(getAnthropicToolChoice("auto", null)).toBeNull();
  });

  test("handles 'auto' string", () => {
    expect(getAnthropicToolChoice("auto")).toEqual({ type: "auto" });
  });

  test("handles 'required' string", () => {
    expect(getAnthropicToolChoice("required")).toEqual({ type: "any" });
  });

  test("handles 'none' string", () => {
    expect(getAnthropicToolChoice("none")).toEqual({ type: "none" });
  });

  test("handles bare tool name string", () => {
    expect(getAnthropicToolChoice("js")).toEqual({ type: "tool", name: "js" });
  });

  test("handles object-form { type, name } without double-wrapping", () => {
    const result = getAnthropicToolChoice({ type: "tool", name: "js" });
    expect(result).toEqual({ type: "tool", name: "js" });
  });

  test("extracts name from object-form with different type", () => {
    const result = getAnthropicToolChoice({ type: "function", name: "my_tool" });
    expect(result).toEqual({ type: "tool", name: "my_tool" });
  });
});

// ── OpenAI provider ─────────────────────────────────────────────────

describe("ChatOpenAI.getToolChoice", () => {
  test("returns null when tool_choice is null", () => {
    expect(getOpenAIToolChoice(null)).toBeNull();
  });

  test("handles 'auto' string", () => {
    expect(getOpenAIToolChoice("auto")).toBe("auto");
  });

  test("handles 'required' string", () => {
    expect(getOpenAIToolChoice("required")).toBe("required");
  });

  test("handles 'none' string", () => {
    expect(getOpenAIToolChoice("none")).toBe("none");
  });

  test("handles bare tool name string", () => {
    expect(getOpenAIToolChoice("js")).toEqual({
      type: "function",
      function: { name: "js" },
    });
  });

  test("handles object-form { type, name } without double-wrapping", () => {
    const result = getOpenAIToolChoice({ type: "tool", name: "js" });
    expect(result).toEqual({ type: "function", function: { name: "js" } });
  });
});
