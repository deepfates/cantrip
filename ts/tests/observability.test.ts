import { describe, expect, test } from "bun:test";

import {
  clearObserver,
  observe,
  observe_debug,
  setObserver,
} from "../src/observability";

describe("observability", () => {
  test("observer hooks are called for async functions", async () => {
    const calls: string[] = [];
    setObserver({
      onStart: () => {
        calls.push("start");
      },
      onEnd: () => {
        calls.push("end");
      },
    });

    const fn = observe(async (x: number) => x + 1, { name: "plus" });
    const result = await fn(1);
    expect(result).toBe(2);
    expect(calls).toEqual(["start", "end"]);
    clearObserver();
  });

  test("observe returns function with same behavior", async () => {
    const fn = observe(async (x: number) => x + 1);
    const result = await fn(1);
    expect(result).toBe(2);
  });

  test("observe_debug returns function with same behavior", () => {
    const fn = observe_debug((x: number) => x * 2);
    expect(fn(2)).toBe(4);
  });

  test("observe_debug sets debug flag", () => {
    const events: boolean[] = [];
    setObserver({
      onStart: (event) => {
        events.push(event.debug);
      },
    });
    const fn = observe_debug((x: number) => x + 1, { name: "dbg" });
    fn(1);
    clearObserver();
    expect(events).toEqual([true]);
  });
});
