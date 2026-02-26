import type { ChatInvokeUsage } from "../views";

export type UsageEntry = {
  model: string;
  timestamp: Date;
  usage: ChatInvokeUsage;
};

export type ModelUsageStats = {
  model: string;
  prompt_tokens: number;
  prompt_cached_tokens: number;
  completion_tokens: number;
  total_tokens: number;
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
  total_prompt_cached_tokens: number;
  total_completion_tokens: number;
  total_tokens: number;
  entry_count: number;
  by_model: Record<string, ModelUsageStats>;
};

export class UsageTracker {
  private history: UsageEntry[] = [];

  add(model: string, usage: ChatInvokeUsage, timestamp = new Date()): UsageEntry {
    const entry = { model, timestamp, usage };
    this.history.push(entry);
    return entry;
  }

  clear(): void {
    this.history = [];
  }

  getHistory(): UsageEntry[] {
    return [...this.history];
  }

  getUsageTokensForModel(model: string): ModelUsageTokens {
    const filtered = this.history.filter((u) => u.model === model);
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
    let filtered = this.history;
    if (model) filtered = filtered.filter((u) => u.model === model);
    if (since) filtered = filtered.filter((u) => u.timestamp >= since);

    if (!filtered.length) {
      return {
        total_prompt_tokens: 0,
        total_prompt_cached_tokens: 0,
        total_completion_tokens: 0,
        total_tokens: 0,
        entry_count: 0,
        by_model: {},
      };
    }

    const modelStats: Record<string, ModelUsageStats> = {};
    for (const entry of filtered) {
      if (!modelStats[entry.model]) {
        modelStats[entry.model] = {
          model: entry.model,
          prompt_tokens: 0,
          prompt_cached_tokens: 0,
          completion_tokens: 0,
          total_tokens: 0,
          invocations: 0,
          average_tokens_per_invocation: 0,
        };
      }
      const stats = modelStats[entry.model];
      stats.prompt_tokens += entry.usage.prompt_tokens;
      stats.prompt_cached_tokens += entry.usage.prompt_cached_tokens ?? 0;
      stats.completion_tokens += entry.usage.completion_tokens;
      stats.total_tokens +=
        entry.usage.prompt_tokens + entry.usage.completion_tokens;
      stats.invocations += 1;
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
    const total_prompt_cached_tokens = filtered.reduce(
      (sum, u) => sum + (u.usage.prompt_cached_tokens ?? 0),
      0,
    );
    const total_completion_tokens = filtered.reduce(
      (sum, u) => sum + u.usage.completion_tokens,
      0,
    );

    return {
      total_prompt_tokens,
      total_prompt_cached_tokens,
      total_completion_tokens,
      total_tokens: total_prompt_tokens + total_completion_tokens,
      entry_count: filtered.length,
      by_model: modelStats,
    };
  }
}
