import { describe, expect, test } from "bun:test";

import { TokenCost } from "../src/tokens/service";

const pricingPayload = {
  "openai/gpt-test": {
    input_cost_per_token: 0.001,
    output_cost_per_token: 0.002,
    max_input_tokens: 1000,
  },
};

describe("token cost", () => {
  test("calculates cost with cached tokens", async () => {
    const cost = new TokenCost(true);
    (cost as any).pricing_data = pricingPayload;
    (cost as any).initialized = true;

    const usage = {
      prompt_tokens: 100,
      prompt_cached_tokens: 20,
      prompt_cache_creation_tokens: null,
      completion_tokens: 50,
      total_tokens: 150,
    };

    const calculated = await cost.calculateCost(
      "openai/gpt-test",
      usage as any,
    );
    expect(calculated?.prompt_cost).toBeCloseTo(0.08);
    expect(calculated?.completion_cost).toBeCloseTo(0.1);
  });
});
