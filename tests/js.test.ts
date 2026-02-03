import { describe, test, expect } from "bun:test";
import { js } from "../src/tools/builtins/js";
import { getJsContext, JsContext } from "../src/tools/builtins/js_context";
import type { ToolContent } from "../src/tools/decorator";

describe("js tool", () => {
  function expectString(result: ToolContent): asserts result is string {
    if (typeof result !== "string") {
      throw new Error("Expected string tool output");
    }
  }

  test("executes simple code and returns the result", async () => {
    const vm_context = await JsContext.create();
    const dependency_overrides = new Map([[getJsContext, () => vm_context]]);

    try {
      const result = await js.execute({ code: "2 + 2" }, dependency_overrides);
      expectString(result);
      expect(result).toBe("4");
    } finally {
      vm_context.dispose();
    }
  });

  test("maintains state between calls", async () => {
    const vm_context = await JsContext.create();
    const dependency_overrides = new Map([[getJsContext, () => vm_context]]);

    try {
      const first = await js.execute(
        { code: "const x = 10" },
        dependency_overrides,
      );
      expectString(first);
      expect(first).toBe("undefined");

      const second = await js.execute({ code: "x * 5" }, dependency_overrides);
      expectString(second);
      expect(second).toBe("50");
    } finally {
      vm_context.dispose();
    }
  });

  test("returns formatted errors", async () => {
    const vm_context = await JsContext.create();
    const dependency_overrides = new Map([[getJsContext, () => vm_context]]);

    try {
      const result = await js.execute(
        { code: "function {" },
        dependency_overrides,
      );
      expectString(result);
      expect(result.startsWith("Error:")).toBe(true);
    } finally {
      vm_context.dispose();
    }
  });

  test("truncates large output", async () => {
    const vm_context = await JsContext.create();
    const dependency_overrides = new Map([[getJsContext, () => vm_context]]);

    try {
      const result = await js.execute(
        { code: '"a".repeat(200)', max_output_chars: 100 },
        dependency_overrides,
      );
      expectString(result);
      expect(result).toContain("... [output truncated at 100 chars]");
    } finally {
      vm_context.dispose();
    }
  });

  test("times out long-running code", async () => {
    const vm_context = await JsContext.create();
    const dependency_overrides = new Map([[getJsContext, () => vm_context]]);

    try {
      const result = await js.execute(
        { code: "while(true) {}", timeout_ms: 50 },
        dependency_overrides,
      );
      expectString(result);
      expect(result.startsWith("Error:")).toBe(true);
    } finally {
      vm_context.dispose();
    }
  });
});
