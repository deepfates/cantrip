import { describe, expect, test } from "bun:test";

import type { PricingProvider } from "../src/tokens";
import { CostCalculator } from "../src/tokens";

const pricingProvider: PricingProvider = {
  async getModelPricing(model: string) {
    if (model !== "openai/gpt-test") return null;
    return {
      model,
      input_cost_per_token: 0.001,
      output_cost_per_token: 0.002,
      cache_read_input_token_cost: 0.0005,
      cache_creation_input_token_cost: 0.0008,
      max_input_tokens: 1000,
    };
  },
};

describe("cost calculator", () => {
  test("calculates cost with cached tokens", async () => {
    const calculator = new CostCalculator(pricingProvider);
    const usage = {
      prompt_tokens: 100,
      prompt_cached_tokens: 20,
      prompt_cache_creation_tokens: null,
      completion_tokens: 50,
      total_tokens: 150,
    };

    const calculated = await calculator.calculateCost(
      "openai/gpt-test",
      usage as any,
    );

    expect(calculated?.prompt_cost).toBeCloseTo(0.09);
    expect(calculated?.completion_cost).toBeCloseTo(0.1);
  });
});
