import { describe, expect, test } from "bun:test";
import { loadEnv } from "./helpers/env";

loadEnv();

const hasKey = Boolean(process.env.ANTHROPIC_API_KEY);
const it = hasKey ? test : test.skip;

const model = process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-5";

describe("integration: cantrip API", () => {
  it("cast() returns a result", async () => {
    const { cantrip, Circle, ChatAnthropic, done, gate, max_turns } = await import("../src");

    const crystal = new ChatAnthropic({ model });
    const echo = gate("Echo input", async ({ text }: { text: string }) => text, {
      name: "echo",
      params: { text: "string" },
    });
    const circle = Circle({
      gates: [echo, done],
      wards: [max_turns(5)],
    });

    const spell = cantrip({
      crystal,
      call: { system_prompt: "Call the echo tool with the user's message, then call done with the echoed text." },
      circle,
    });

    const result = await spell.cast("hello");
    expect(result).toBeTruthy();
    expect(typeof result).toBe("string");
  }, 30_000);

  it("invoke() returns an entity, entity.turn() works", async () => {
    const { cantrip, Circle, ChatAnthropic, done, gate, max_turns } = await import("../src");

    const crystal = new ChatAnthropic({ model });
    const echo = gate("Echo input", async ({ text }: { text: string }) => text, {
      name: "echo",
      params: { text: "string" },
    });
    const circle = Circle({
      gates: [echo, done],
      wards: [max_turns(5)],
    });

    const entity = cantrip({
      crystal,
      call: { system_prompt: "Call the echo tool with the user's message, then call done with the echoed text." },
      circle,
    }).invoke();

    expect(entity).toBeTruthy();
    expect(typeof entity.turn).toBe("function");

    const result = await entity.turn("hello");
    expect(result).toBeTruthy();
    expect(typeof result).toBe("string");

    // Multi-turn: second turn sees prior context
    const result2 = await entity.turn("say more");
    expect(result2).toBeTruthy();
    expect(typeof result2).toBe("string");
  }, 60_000);

  it("two casts of same cantrip are independent", async () => {
    const { cantrip, Circle, ChatAnthropic, done, gate, max_turns } = await import("../src");

    const crystal = new ChatAnthropic({ model });

    let callCount = 0;
    const counter = gate("Increment counter", async () => {
      callCount++;
      return `count: ${callCount}`;
    }, {
      name: "count",
      params: {},
    });
    const circle = Circle({
      gates: [counter, done],
      wards: [max_turns(5)],
    });

    const spell = cantrip({
      crystal,
      call: { system_prompt: "Call the count tool once, then call done with the result." },
      circle,
    });

    // Reset for each cast to prove independence
    callCount = 0;
    const result1 = await spell.cast("count");
    const count1 = callCount;

    callCount = 0;
    const result2 = await spell.cast("count");
    const count2 = callCount;

    // Both casts should have called the tool — they're independent (CANTRIP-2)
    expect(count1).toBeGreaterThan(0);
    expect(count2).toBeGreaterThan(0);
    expect(result1).toBeTruthy();
    expect(result2).toBeTruthy();
  }, 60_000);
});
