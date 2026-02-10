/**
 * Tests for the correctness fixes surfaced by Codex review:
 * 1. safeStringify — handles cyclic/non-serializable data
 * 2. llm_batch — validates task queries before calling .slice()
 * 3. Browser profile filtering in system prompts
 */
import { describe, expect, test } from "bun:test";
import { safeStringify } from "../src/rlm/tools";
import { getRlmSystemPrompt, getRlmMemorySystemPrompt } from "../src/rlm/prompt";

// ---------------------------------------------------------------------------
// 1. safeStringify
// ---------------------------------------------------------------------------
describe("safeStringify", () => {
  test("serializes plain objects", () => {
    expect(safeStringify({ a: 1 })).toBe('{"a":1}');
  });

  test("supports indent parameter", () => {
    expect(safeStringify({ a: 1 }, 2)).toBe('{\n  "a": 1\n}');
  });

  test("returns [unserializable] for cyclic data", () => {
    const obj: any = { name: "root" };
    obj.self = obj; // circular reference
    expect(safeStringify(obj)).toBe("[unserializable]");
  });

  test("returns [unserializable] for BigInt values", () => {
    // JSON.stringify throws on BigInt
    expect(safeStringify({ n: BigInt(42) })).toBe("[unserializable]");
  });

  test("handles null and undefined", () => {
    expect(safeStringify(null)).toBe("null");
    expect(safeStringify(undefined)).toBe(undefined as any); // JSON.stringify(undefined) returns undefined
  });

  test("handles arrays with nested cycles", () => {
    const arr: any[] = [1, 2];
    arr.push(arr);
    expect(safeStringify(arr)).toBe("[unserializable]");
  });
});

// ---------------------------------------------------------------------------
// 2. Browser profile filtering in system prompts
// ---------------------------------------------------------------------------
describe("browser profile filtering in system prompts", () => {
  const baseOpts = {
    contextType: "String",
    contextLength: 100,
    contextPreview: "hello world",
  };

  test("full profile includes all browser sections", () => {
    const prompt = getRlmSystemPrompt({
      ...baseOpts,
      hasBrowser: true,
      // no browserAllowedFunctions → full profile (all functions documented)
    });

    expect(prompt).toContain("BROWSER AUTOMATION");
    expect(prompt).toContain("openTab(url)");
    expect(prompt).toContain("setCookie");
    expect(prompt).toContain("emulateDevice");
    expect(prompt).toContain("dragAndDrop");
    expect(prompt).toContain("Multi-tab example");
  });

  test("readonly profile omits write actions and tabs", () => {
    // A restricted set: only selectors, navigation, and read-only functions
    const readonlyFns = new Set([
      "button", "link", "text", "textBox", "$",
      "near", "above", "below",
      "goto", "currentURL", "title",
      "evaluate", "waitFor", "screenshot",
    ]);

    const prompt = getRlmSystemPrompt({
      ...baseOpts,
      hasBrowser: true,
      browserAllowedFunctions: readonlyFns,
    });

    expect(prompt).toContain("BROWSER AUTOMATION");
    // Should have the allowed functions
    expect(prompt).toContain("button(text)");
    expect(prompt).toContain("goto(url)");
    expect(prompt).toContain("evaluate");

    // Should NOT have the disallowed functions
    expect(prompt).not.toContain("openTab(url)");
    expect(prompt).not.toContain("setCookie");
    expect(prompt).not.toContain("emulateDevice");
    expect(prompt).not.toContain("dragAndDrop");
    // Multi-tab example needs openTab+switchTo+closeTab — should be absent
    expect(prompt).not.toContain("Multi-tab example");
  });

  test("no browser flag omits entire browser section", () => {
    const prompt = getRlmSystemPrompt({
      ...baseOpts,
      hasBrowser: false,
    });

    expect(prompt).not.toContain("BROWSER AUTOMATION");
    expect(prompt).not.toContain("openTab");
  });

  test("memory prompt respects browser profile filtering", () => {
    const readonlyFns = new Set([
      "button", "link", "text",
      "goto", "currentURL", "title",
      "evaluate",
    ]);

    const prompt = getRlmMemorySystemPrompt({
      hasData: false,
      windowSize: 5,
      hasBrowser: true,
      browserAllowedFunctions: readonlyFns,
    });

    expect(prompt).toContain("BROWSER AUTOMATION");
    expect(prompt).toContain("button(text)");
    expect(prompt).toContain("goto(url)");
    // Should not document functions outside the allowed set
    expect(prompt).not.toContain("openTab(url)");
    expect(prompt).not.toContain("setCookie");
    expect(prompt).not.toContain("Multi-tab example");
  });

  test("memory prompt with no browser omits section", () => {
    const prompt = getRlmMemorySystemPrompt({
      hasData: true,
      dataType: "String",
      dataLength: 50,
      dataPreview: "test data",
      windowSize: 5,
      hasBrowser: false,
    });

    expect(prompt).not.toContain("BROWSER AUTOMATION");
  });

  test("interactive profile includes actions but not emulation", () => {
    // Interactive profile: selectors, actions, navigation, but no emulation/cookies
    const interactiveFns = new Set([
      "button", "link", "text", "textBox", "$",
      "near", "above", "below", "toLeftOf", "toRightOf",
      "click", "doubleClick", "write", "clear", "press",
      "hover", "focus", "scrollTo", "scrollDown", "scrollUp",
      "goto", "reload", "goBack", "goForward", "currentURL", "title",
      "evaluate", "waitFor", "screenshot",
      "accept", "dismiss",
    ]);

    const prompt = getRlmSystemPrompt({
      ...baseOpts,
      hasBrowser: true,
      browserAllowedFunctions: interactiveFns,
    });

    // Should have actions
    expect(prompt).toContain("click(selector");
    expect(prompt).toContain("write(text");

    // Should NOT have emulation or cookies
    expect(prompt).not.toContain("emulateDevice");
    expect(prompt).not.toContain("setCookie");
    expect(prompt).not.toContain("openTab(url)");
  });
});
