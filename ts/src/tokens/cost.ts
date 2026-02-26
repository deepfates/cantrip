import type { ChatInvokeUsage } from "../llm/views";
import type { PricingProvider } from "./pricing";

export type TokenCostCalculated = {
  new_prompt_tokens: number;
  new_prompt_cost: number;
  prompt_read_cached_tokens?: number | null;
  prompt_read_cached_cost?: number | null;
  prompt_cached_creation_tokens?: number | null;
  prompt_cache_creation_cost?: number | null;
  completion_tokens: number;
  completion_cost: number;
  prompt_cost: number;
  total_cost: number;
};

export class CostCalculator {
  constructor(private pricing: PricingProvider) {}

  async calculateCost(
    model: string,
    usage: ChatInvokeUsage,
  ): Promise<TokenCostCalculated | null> {
    const pricing = await this.pricing.getModelPricing(model);
    if (!pricing) return null;

    const uncachedPromptTokens =
      usage.prompt_tokens - (usage.prompt_cached_tokens ?? 0);

    const prompt_read_cached_cost =
      usage.prompt_cached_tokens && pricing.cache_read_input_token_cost
        ? usage.prompt_cached_tokens * pricing.cache_read_input_token_cost
        : null;

    const prompt_cache_creation_cost =
      usage.prompt_cache_creation_tokens &&
      pricing.cache_creation_input_token_cost
        ? usage.prompt_cache_creation_tokens *
          pricing.cache_creation_input_token_cost
        : null;

    const completion_cost =
      usage.completion_tokens * Number(pricing.output_cost_per_token ?? 0);

    const new_prompt_cost =
      uncachedPromptTokens * Number(pricing.input_cost_per_token ?? 0);

    return {
      new_prompt_tokens: usage.prompt_tokens,
      new_prompt_cost,
      prompt_read_cached_tokens: usage.prompt_cached_tokens ?? null,
      prompt_read_cached_cost,
      prompt_cached_creation_tokens: usage.prompt_cache_creation_tokens ?? null,
      prompt_cache_creation_cost,
      completion_tokens: usage.completion_tokens,
      completion_cost,
      prompt_cost:
        new_prompt_cost +
        (prompt_read_cached_cost ?? 0) +
        (prompt_cache_creation_cost ?? 0),
      total_cost:
        new_prompt_cost +
        (prompt_read_cached_cost ?? 0) +
        (prompt_cache_creation_cost ?? 0) +
        completion_cost,
    };
  }
}
