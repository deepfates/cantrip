import { describe, expect, test } from "bun:test";

import { observe, observe_debug } from "../src/observability";

describe("observability", () => {
  test("observe returns function with same behavior", async () => {
    const fn = observe(async (x: number) => x + 1);
    const result = await fn(1);
    expect(result).toBe(2);
  });

  test("observe_debug returns function with same behavior", () => {
    const fn = observe_debug((x: number) => x * 2);
    expect(fn(2)).toBe(4);
  });
});
