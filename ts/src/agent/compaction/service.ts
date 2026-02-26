import type { BaseChatModel } from "../../llm/base";
import type { AnyMessage } from "../../llm/messages";
import type { ChatInvokeUsage } from "../../llm/views";
import type { PricingProvider } from "../../tokens";
import {
  DEFAULT_SUMMARY_PROMPT,
  DEFAULT_THRESHOLD_RATIO,
  type CompactionConfig,
  type CompactionResult,
  tokenUsageFromUsage,
} from "./models";
const DEFAULT_CONTEXT_WINDOW = 128_000;

export class CompactionService {
  config: Required<CompactionConfig>;
  llm?: BaseChatModel;
  pricing_provider?: PricingProvider;
  private last_usage = tokenUsageFromUsage(null);
  private context_limit_cache: Record<string, number> = {};
  private threshold_cache: Record<string, number> = {};

  constructor(options: {
    config?: CompactionConfig;
    llm?: BaseChatModel;
    pricing_provider?: PricingProvider;
  }) {
    this.config = {
      enabled: options.config?.enabled ?? true,
      threshold_ratio:
        options.config?.threshold_ratio ?? DEFAULT_THRESHOLD_RATIO,
      model: options.config?.model ?? null,
      summary_prompt: options.config?.summary_prompt ?? DEFAULT_SUMMARY_PROMPT,
    };
    this.llm = options.llm;
    this.pricing_provider = options.pricing_provider;
  }

  updateUsage(usage?: ChatInvokeUsage | null): void {
    this.last_usage = tokenUsageFromUsage(usage ?? null);
  }

  async getModelContextLimit(model: string): Promise<number> {
    if (this.context_limit_cache[model]) return this.context_limit_cache[model];

    let limit = DEFAULT_CONTEXT_WINDOW;
    if (this.pricing_provider) {
      try {
        const pricing = await this.pricing_provider.getModelPricing(model);
        if (pricing?.max_input_tokens) limit = pricing.max_input_tokens;
        else if (pricing?.max_tokens) limit = pricing.max_tokens;
      } catch {}
    }

    this.context_limit_cache[model] = limit;
    return limit;
  }

  async getThresholdForModel(model: string): Promise<number> {
    if (this.threshold_cache[model]) return this.threshold_cache[model];
    const limit = await this.getModelContextLimit(model);
    const threshold = Math.floor(limit * this.config.threshold_ratio);
    this.threshold_cache[model] = threshold;
    return threshold;
  }

  async shouldCompact(model: string): Promise<boolean> {
    if (!this.config.enabled) return false;
    const threshold = await this.getThresholdForModel(model);
    return this.last_usage.total_tokens >= threshold;
  }

  async compact(
    messages: AnyMessage[],
    llm?: BaseChatModel,
  ): Promise<CompactionResult> {
    const model = llm ?? this.llm;
    if (!model) throw new Error("No LLM available for compaction.");

    const original_tokens = this.last_usage.total_tokens;

    const prepared = this.prepareMessagesForSummary(messages);
    prepared.push({ role: "user", content: this.config.summary_prompt } as any);

    const response = await model.ainvoke(prepared);
    const summaryText = response.content ?? "";
    const extracted = this.extractSummary(summaryText);

    return {
      compacted: true,
      original_tokens,
      new_tokens: response.usage?.completion_tokens ?? 0,
      summary: extracted,
    };
  }

  async checkAndCompact(
    messages: AnyMessage[],
    llm?: BaseChatModel,
  ): Promise<{ messages: AnyMessage[]; result: CompactionResult }> {
    const model = llm ?? this.llm;
    if (!model)
      return {
        messages,
        result: { compacted: false, original_tokens: 0, new_tokens: 0 },
      };
    if (!(await this.shouldCompact(model.model))) {
      return {
        messages,
        result: { compacted: false, original_tokens: 0, new_tokens: 0 },
      };
    }

    const result = await this.compact(messages, llm);
    const newMessages: AnyMessage[] = [];
    // Preserve the system prompt (CALL-2: system prompt MUST be first message;
    // CALL-5: folding MUST NOT alter the call)
    const systemMsg = messages.find((m) => m.role === "system");
    if (systemMsg) newMessages.push(systemMsg);
    newMessages.push({ role: "user", content: result.summary ?? "" } as any);
    return { messages: newMessages, result };
  }

  private prepareMessagesForSummary(messages: AnyMessage[]): AnyMessage[] {
    return JSON.parse(JSON.stringify(messages)) as AnyMessage[];
  }

  private extractSummary(text: string): string {
    const match = text.match(/<summary>([\s\S]*?)<\/summary>/i);
    return match ? match[1].trim() : text.trim();
  }
}
