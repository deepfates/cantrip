import { promises as fs } from "fs";
import os from "os";
import path from "path";
import type { ChatInvokeUsage } from "../llm/views";
import { CUSTOM_MODEL_PRICING } from "./custom_pricing";
import { MODEL_TO_LITELLM } from "./mappings";
import type {
  CachedPricingData,
  ModelPricing,
  ModelUsageStats,
  ModelUsageTokens,
  TokenCostCalculated,
  TokenUsageEntry,
  UsageSummary,
} from "./views";

const CACHE_DIR_NAME = "bu_agent_sdk/token_cost";
const CACHE_DURATION_MS = 24 * 60 * 60 * 1000;
const PRICING_URL =
  "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json";

function xdgCacheHome(): string {
  const env = process.env.XDG_CACHE_HOME;
  if (env && path.isAbsolute(env)) return env;
  return path.join(os.homedir(), ".cache");
}

export class TokenCost {
  include_cost: boolean;
  usage_history: TokenUsageEntry[] = [];
  private pricing_data: Record<string, any> | null = null;
  private initialized = false;
  private cache_dir = path.join(xdgCacheHome(), CACHE_DIR_NAME);

  constructor(include_cost = false) {
    this.include_cost =
      include_cost ||
      (process.env.BU_AGENT_SDK_CALCULATE_COST ?? "true").toLowerCase() ===
        "true";
  }

  async initialize(): Promise<void> {
    if (!this.initialized) {
      if (this.include_cost) await this.loadPricingData();
      this.initialized = true;
    }
  }

  private async loadPricingData(): Promise<void> {
    const cacheFile = await this.findValidCache();
    if (cacheFile) {
      await this.loadFromCache(cacheFile);
    } else {
      await this.fetchAndCachePricingData();
    }
  }

  private async findValidCache(): Promise<string | null> {
    try {
      await fs.mkdir(this.cache_dir, { recursive: true });
      const files = await fs.readdir(this.cache_dir);
      const jsonFiles = files.filter((f) => f.endsWith(".json"));
      if (!jsonFiles.length) return null;

      const withStats = await Promise.all(
        jsonFiles.map(async (file) => {
          const full = path.join(this.cache_dir, file);
          const stat = await fs.stat(full);
          return { full, mtime: stat.mtimeMs };
        }),
      );

      withStats.sort((a, b) => b.mtime - a.mtime);
      for (const file of withStats) {
        if (await this.isCacheValid(file.full)) return file.full;
        try {
          await fs.unlink(file.full);
        } catch {}
      }
      return null;
    } catch {
      return null;
    }
  }

  private async isCacheValid(cacheFile: string): Promise<boolean> {
    try {
      const raw = await fs.readFile(cacheFile, "utf8");
      const cached = JSON.parse(raw) as CachedPricingData;
      const ts = new Date(cached.timestamp).getTime();
      return Date.now() - ts < CACHE_DURATION_MS;
    } catch {
      return false;
    }
  }

  private async loadFromCache(cacheFile: string): Promise<void> {
    try {
      const raw = await fs.readFile(cacheFile, "utf8");
      const cached = JSON.parse(raw) as CachedPricingData;
      this.pricing_data = cached.data ?? {};
    } catch {
      await this.fetchAndCachePricingData();
    }
  }

  private async fetchAndCachePricingData(): Promise<void> {
    try {
      const response = await fetch(PRICING_URL);
      if (!response.ok)
        throw new Error(`Failed to fetch pricing: ${response.status}`);
      this.pricing_data = await response.json();

      const cached: CachedPricingData = {
        timestamp: new Date().toISOString(),
        data: this.pricing_data ?? {},
      };

      await fs.mkdir(this.cache_dir, { recursive: true });
      const filename = `pricing_${new Date().toISOString().replace(/[:.]/g, "-")}.json`;
      const cacheFile = path.join(this.cache_dir, filename);
      await fs.writeFile(cacheFile, JSON.stringify(cached, null, 2));
    } catch {
      this.pricing_data = {};
    }
  }

  private findModelInPricingData(
    model_name: string,
  ): Record<string, any> | null {
    if (!this.pricing_data) return null;

    if (model_name in this.pricing_data) return this.pricing_data[model_name];

    const mapped = MODEL_TO_LITELLM[model_name];
    if (mapped && this.pricing_data[mapped]) return this.pricing_data[mapped];

    const prefixes = ["anthropic/", "openai/", "google/", "azure/", "bedrock/"];
    for (const prefix of prefixes) {
      const prefixed = `${prefix}${model_name}`;
      if (this.pricing_data[prefixed]) return this.pricing_data[prefixed];
    }

    if (model_name.includes("/")) {
      const bare = model_name.split("/", 2)[1];
      if (this.pricing_data[bare]) return this.pricing_data[bare];
    }

    return null;
  }

  async getModelPricing(model_name: string): Promise<ModelPricing | null> {
    if (!this.initialized) await this.initialize();

    if (CUSTOM_MODEL_PRICING[model_name]) {
      const data = CUSTOM_MODEL_PRICING[model_name];
      return {
        model: model_name,
        input_cost_per_token: data.input_cost_per_token,
        output_cost_per_token: data.output_cost_per_token,
        max_tokens: data.max_tokens,
        max_input_tokens: data.max_input_tokens,
        max_output_tokens: data.max_output_tokens,
        cache_read_input_token_cost: data.cache_read_input_token_cost,
        cache_creation_input_token_cost: data.cache_creation_input_token_cost,
      };
    }

    const data = this.findModelInPricingData(model_name);
    if (!data) return null;

    return {
      model: model_name,
      input_cost_per_token: data.input_cost_per_token,
      output_cost_per_token: data.output_cost_per_token,
      max_tokens: data.max_tokens,
      max_input_tokens: data.max_input_tokens,
      max_output_tokens: data.max_output_tokens,
      cache_read_input_token_cost: data.cache_read_input_token_cost,
      cache_creation_input_token_cost: data.cache_creation_input_token_cost,
    };
  }

  async calculateCost(
    model: string,
    usage: ChatInvokeUsage,
  ): Promise<TokenCostCalculated | null> {
    if (!this.include_cost) return null;
    const pricing = await this.getModelPricing(model);
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

  addUsage(model: string, usage: ChatInvokeUsage): TokenUsageEntry {
    const entry = { model, timestamp: new Date(), usage };
    this.usage_history.push(entry);
    return entry;
  }

  getUsageTokensForModel(model: string): ModelUsageTokens {
    const filtered = this.usage_history.filter((u) => u.model === model);
    const prompt = filtered.reduce((sum, u) => sum + u.usage.prompt_tokens, 0);
    const cached = filtered.reduce(
      (sum, u) => sum + (u.usage.prompt_cached_tokens ?? 0),
      0,
    );
    const completion = filtered.reduce(
      (sum, u) => sum + u.usage.completion_tokens,
      0,
    );
    return {
      model,
      prompt_tokens: prompt,
      prompt_cached_tokens: cached,
      completion_tokens: completion,
      total_tokens: prompt + completion,
    };
  }

  async getUsageSummary(model?: string, since?: Date): Promise<UsageSummary> {
    let filtered = this.usage_history;
    if (model) filtered = filtered.filter((u) => u.model === model);
    if (since) filtered = filtered.filter((u) => u.timestamp >= since);

    if (!filtered.length) {
      return {
        total_prompt_tokens: 0,
        total_prompt_cost: 0,
        total_prompt_cached_tokens: 0,
        total_prompt_cached_cost: 0,
        total_completion_tokens: 0,
        total_completion_cost: 0,
        total_tokens: 0,
        total_cost: 0,
        entry_count: 0,
        by_model: {},
      };
    }

    const modelStats: Record<string, ModelUsageStats> = {};
    let total_prompt_cost = 0;
    let total_completion_cost = 0;
    let total_prompt_cached_cost = 0;

    for (const entry of filtered) {
      if (!modelStats[entry.model]) {
        modelStats[entry.model] = {
          model: entry.model,
          prompt_tokens: 0,
          completion_tokens: 0,
          total_tokens: 0,
          cost: 0,
          invocations: 0,
          average_tokens_per_invocation: 0,
        };
      }
      const stats = modelStats[entry.model];
      stats.prompt_tokens += entry.usage.prompt_tokens;
      stats.completion_tokens += entry.usage.completion_tokens;
      stats.total_tokens +=
        entry.usage.prompt_tokens + entry.usage.completion_tokens;
      stats.invocations += 1;

      if (this.include_cost) {
        const cost = await this.calculateCost(entry.model, entry.usage);
        if (cost) {
          stats.cost += cost.total_cost;
          total_prompt_cost += cost.prompt_cost;
          total_completion_cost += cost.completion_cost;
          total_prompt_cached_cost += cost.prompt_read_cached_cost ?? 0;
        }
      }
    }

    for (const stats of Object.values(modelStats)) {
      if (stats.invocations > 0) {
        stats.average_tokens_per_invocation =
          stats.total_tokens / stats.invocations;
      }
    }

    const total_prompt_tokens = filtered.reduce(
      (sum, u) => sum + u.usage.prompt_tokens,
      0,
    );
    const total_completion_tokens = filtered.reduce(
      (sum, u) => sum + u.usage.completion_tokens,
      0,
    );
    const total_prompt_cached_tokens = filtered.reduce(
      (sum, u) => sum + (u.usage.prompt_cached_tokens ?? 0),
      0,
    );

    return {
      total_prompt_tokens,
      total_prompt_cost,
      total_prompt_cached_tokens,
      total_prompt_cached_cost: total_prompt_cached_cost,
      total_completion_tokens,
      total_completion_cost,
      total_tokens: total_prompt_tokens + total_completion_tokens,
      total_cost:
        total_prompt_cost + total_completion_cost + total_prompt_cached_cost,
      entry_count: filtered.length,
      by_model: modelStats,
    };
  }

  formatTokens(tokens: number): string {
    if (tokens >= 1_000_000_000)
      return `${(tokens / 1_000_000_000).toFixed(1)}B`;
    if (tokens >= 1_000_000) return `${(tokens / 1_000_000).toFixed(1)}M`;
    if (tokens >= 1_000) return `${(tokens / 1_000).toFixed(1)}k`;
    return String(tokens);
  }

  async getCostByModel(): Promise<Record<string, ModelUsageStats>> {
    const summary = await this.getUsageSummary();
    return summary.by_model;
  }

  clearHistory(): void {
    this.usage_history = [];
  }

  async refreshPricingData(): Promise<void> {
    if (this.include_cost) await this.fetchAndCachePricingData();
  }

  async cleanOldCaches(keep_count = 3): Promise<void> {
    try {
      const files = (await fs.readdir(this.cache_dir)).filter((f) =>
        f.endsWith(".json"),
      );
      if (files.length <= keep_count) return;
      const withStats = await Promise.all(
        files.map(async (file) => {
          const full = path.join(this.cache_dir, file);
          const stat = await fs.stat(full);
          return { full, mtime: stat.mtimeMs };
        }),
      );
      withStats.sort((a, b) => a.mtime - b.mtime);
      for (const file of withStats.slice(
        0,
        Math.max(0, withStats.length - keep_count),
      )) {
        try {
          await fs.unlink(file.full);
        } catch {}
      }
    } catch {}
  }

  async ensurePricingLoaded(): Promise<void> {
    if (!this.initialized && this.include_cost) {
      await this.initialize();
    }
  }
}
