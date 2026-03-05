import { describe, test, expect } from "bun:test";
import { JsContext } from "../../src/circle/medium/js/context";

describe("JsContext", () => {
  test("executes simple code and returns the result", async () => {
    const ctx = await JsContext.create();
    try {
      const result = await ctx.evalCode("2 + 2");
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.output).toBe("4");
    } finally {
      ctx.dispose();
    }
  });

  test("maintains state between calls", async () => {
    const ctx = await JsContext.create();
    try {
      const first = await ctx.evalCode("const x = 10");
      expect(first.ok).toBe(true);
      if (first.ok) expect(first.output).toBe("undefined");

      const second = await ctx.evalCode("x * 5");
      expect(second.ok).toBe(true);
      if (second.ok) expect(second.output).toBe("50");
    } finally {
      ctx.dispose();
    }
  });

  test("returns errors for invalid code", async () => {
    const ctx = await JsContext.create();
    try {
      const result = await ctx.evalCode("function {");
      expect(result.ok).toBe(false);
    } finally {
      ctx.dispose();
    }
  });

  test("times out long-running code", async () => {
    const ctx = await JsContext.create();
    try {
      const result = await ctx.evalCode("while(true) {}", {
        executionTimeoutMs: 50,
      });
      expect(result.ok).toBe(false);
    } finally {
      ctx.dispose();
    }
  });
});
