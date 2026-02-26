import { describe, expect, test } from "bun:test";

import { UsageTracker } from "../src/tokens";

describe("usage tracker", () => {
  test("summarizes usage by model", async () => {
    const tracker = new UsageTracker();
    const now = new Date("2026-01-01T00:00:00Z");
    const later = new Date("2026-01-02T00:00:00Z");

    tracker.add(
      "model-a",
      { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
      now,
    );
    tracker.add(
      "model-a",
      { prompt_tokens: 20, completion_tokens: 10, total_tokens: 30 },
      later,
    );
    tracker.add(
      "model-b",
      { prompt_tokens: 3, completion_tokens: 2, total_tokens: 5 },
      later,
    );

    const modelATotals = tracker.getUsageTokensForModel("model-a");
    expect(modelATotals.total_tokens).toBe(45);
    expect(modelATotals.prompt_tokens).toBe(30);
    expect(modelATotals.completion_tokens).toBe(15);

    const summary = await tracker.getUsageSummary();
    expect(summary.total_tokens).toBe(50);
    expect(summary.entry_count).toBe(3);
    expect(summary.by_model["model-a"].invocations).toBe(2);
    expect(summary.by_model["model-b"].invocations).toBe(1);
  });

  test("filters usage by model and time", async () => {
    const tracker = new UsageTracker();
    const old = new Date("2026-01-01T00:00:00Z");
    const recent = new Date("2026-01-03T00:00:00Z");

    tracker.add(
      "model-a",
      { prompt_tokens: 5, completion_tokens: 5, total_tokens: 10 },
      old,
    );
    tracker.add(
      "model-a",
      { prompt_tokens: 7, completion_tokens: 3, total_tokens: 10 },
      recent,
    );
    tracker.add(
      "model-b",
      { prompt_tokens: 2, completion_tokens: 1, total_tokens: 3 },
      recent,
    );

    const since = new Date("2026-01-02T00:00:00Z");
    const filtered = await tracker.getUsageSummary("model-a", since);
    expect(filtered.entry_count).toBe(1);
    expect(filtered.total_tokens).toBe(10);
  });
});
