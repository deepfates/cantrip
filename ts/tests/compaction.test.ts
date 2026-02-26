import { describe, expect, test } from "bun:test";

import { CompactionService } from "../src/agent/compaction/service";
import type { PricingProvider } from "../src/tokens";

const dummyLLM = {
  model: "dummy-model",
  provider: "dummy",
  name: "dummy",
  async ainvoke() {
    return {
      content: "<summary>Short summary</summary>",
      tool_calls: [],
      usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
    };
  },
};

describe("compaction", () => {
  test("extracts summary tags", async () => {
    const service = new CompactionService({ llm: dummyLLM as any });
    service.updateUsage({
      prompt_tokens: 100,
      completion_tokens: 50,
      total_tokens: 150,
    });

    const result = await service.compact([
      { role: "user", content: "hi" } as any,
    ]);
    expect(result.summary).toBe("Short summary");
  });

  test("checkAndCompact replaces history", async () => {
    const service = new CompactionService({
      llm: dummyLLM as any,
      config: { threshold_ratio: 0 },
    });
    service.updateUsage({
      prompt_tokens: 1,
      completion_tokens: 1,
      total_tokens: 2,
    });

    const { messages, result } = await service.checkAndCompact([
      { role: "user", content: "hello" } as any,
    ]);

    expect(result.compacted).toBe(true);
    expect(messages.length).toBe(1);
    expect(messages[0].content).toBe("Short summary");
  });

  test("uses pricing provider for context limit", async () => {
    const pricingProvider: PricingProvider = {
      async getModelPricing(model: string) {
        if (model !== "dummy-model") return null;
        return { model, max_input_tokens: 1000 };
      },
    };

    const service = new CompactionService({
      llm: dummyLLM as any,
      config: { threshold_ratio: 0.5 },
      pricing_provider: pricingProvider,
    });
    service.updateUsage({
      prompt_tokens: 600,
      completion_tokens: 0,
      total_tokens: 600,
    });

    expect(await service.shouldCompact("dummy-model")).toBe(true);
  });
});
