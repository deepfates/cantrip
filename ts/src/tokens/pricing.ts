import { promises as fs } from "fs";
import os from "os";
import path from "path";
import { CUSTOM_MODEL_PRICING } from "./custom_pricing";
import { MODEL_TO_LITELLM } from "./mappings";

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

export type PricingProvider = {
  getModelPricing(model: string): Promise<ModelPricing | null>;
};

const CACHE_DIR_NAME = "bu_agent_sdk/token_cost";
const CACHE_DURATION_MS = 24 * 60 * 60 * 1000;
const PRICING_URL =
  "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json";

function xdgCacheHome(): string {
  const env = process.env.XDG_CACHE_HOME;
  if (env && path.isAbsolute(env)) return env;
  return path.join(os.homedir(), ".cache");
}

export class LiteLLMPricingProvider implements PricingProvider {
  private pricing_data: Record<string, any> | null = null;
  private initialized = false;
  private cache_dir: string;

  constructor(
    private options: {
      cache_dir?: string;
      cache_duration_ms?: number;
      pricing_url?: string;
    } = {},
  ) {
    this.cache_dir = options.cache_dir ?? path.join(xdgCacheHome(), CACHE_DIR_NAME);
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

  async initialize(): Promise<void> {
    if (!this.initialized) {
      await this.loadPricingData();
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
      const cacheDuration =
        this.options.cache_duration_ms ?? CACHE_DURATION_MS;
      return Date.now() - ts < cacheDuration;
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
      const response = await fetch(this.options.pricing_url ?? PRICING_URL);
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
}
