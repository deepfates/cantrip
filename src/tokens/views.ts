export type TokenUsageEntry = {
  model: string;
  timestamp: Date;
  usage: any;
};

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

export type ModelPricing = {
  model: string;
  input_cost_per_token?: number | null;
  output_cost_per_token?: number | null;
  cache_read_input_token_cost?: number | null;
  cache_creation_input_token_cost?: number | null;
  max_tokens?: number | null;
  max_input_tokens?: number | null;
  max_output_tokens?: number | null;
};

export type CachedPricingData = {
  timestamp: string;
  data: Record<string, any>;
};

export type ModelUsageStats = {
  model: string;
  prompt_tokens: number;
  completion_tokens: number;
  total_tokens: number;
  cost: number;
  invocations: number;
  average_tokens_per_invocation: number;
};

export type ModelUsageTokens = {
  model: string;
  prompt_tokens: number;
  prompt_cached_tokens: number;
  completion_tokens: number;
  total_tokens: number;
};

export type UsageSummary = {
  total_prompt_tokens: number;
  total_prompt_cost: number;
  total_prompt_cached_tokens: number;
  total_prompt_cached_cost: number;
  total_completion_tokens: number;
  total_completion_cost: number;
  total_tokens: number;
  total_cost: number;
  entry_count: number;
  by_model: Record<string, ModelUsageStats>;
};
