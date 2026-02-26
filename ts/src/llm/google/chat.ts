import crypto from "crypto";
import type { AnyMessage, ToolCall } from "../messages";
import type { BaseChatModel, ToolChoice, ToolDefinition } from "../base";
import { ModelProviderError } from "../exceptions";
import type { ChatInvokeCompletion, ChatInvokeUsage } from "../views";
import { GoogleMessageSerializer } from "./serializer";

export type ChatGoogleOptions = {
  model: string;
  api_key?: string | null;
  base_url?: string | null;
  temperature?: number | null;
  top_p?: number | null;
  seed?: number | null;
  thinking_budget?: number | null;
  max_output_tokens?: number | null;
  config?: Record<string, unknown> | null;
  include_system_in_user?: boolean;
  max_retries?: number;
  retryable_status_codes?: number[];
  retry_base_delay?: number;
  retry_max_delay?: number;
  explicit_context_caching?: boolean;
  explicit_cache_ttl_seconds?: number | null;
};

export class ChatGoogle implements BaseChatModel {
  model: string;
  api_key: string | null;
  base_url: string;
  temperature: number | null;
  top_p: number | null;
  seed: number | null;
  thinking_budget: number | null;
  max_output_tokens: number | null;
  config: Record<string, unknown> | null;
  include_system_in_user: boolean;
  max_retries: number;
  retryable_status_codes: number[];
  retry_base_delay: number;
  retry_max_delay: number;
  explicit_context_caching: boolean;
  explicit_cache_ttl_seconds: number | null;

  private cachedContentName: string | null = null;
  private cachedContentKey: string | null = null;

  constructor(options: ChatGoogleOptions) {
    this.model = options.model;
    this.api_key = options.api_key ?? process.env.GOOGLE_API_KEY ?? null;
    this.base_url = options.base_url ?? "https://generativelanguage.googleapis.com/v1beta";
    this.temperature = options.temperature ?? 0.5;
    this.top_p = options.top_p ?? null;
    this.seed = options.seed ?? null;
    this.thinking_budget = options.thinking_budget ?? null;
    this.max_output_tokens = options.max_output_tokens ?? 8096;
    this.config = options.config ?? null;
    this.include_system_in_user = options.include_system_in_user ?? false;
    this.max_retries = options.max_retries ?? 5;
    this.retryable_status_codes = options.retryable_status_codes ?? [429, 500, 502, 503, 504];
    this.retry_base_delay = options.retry_base_delay ?? 1.0;
    this.retry_max_delay = options.retry_max_delay ?? 60.0;
    this.explicit_context_caching = options.explicit_context_caching ?? true;
    this.explicit_cache_ttl_seconds = options.explicit_cache_ttl_seconds ?? 3600;
  }

  get provider(): string {
    return "google";
  }

  get name(): string {
    return String(this.model);
  }

  private buildCacheKey(system_instruction: string | undefined, tools?: ToolDefinition[] | null): string {
    const toolFingerprint = (tools || []).map((tool) => ({
      name: tool.name,
      description: tool.description,
      parameters: tool.parameters,
    }));
    const payload = {
      model: this.model,
      system_instruction: system_instruction ?? null,
      tools: toolFingerprint,
    };
    const raw = JSON.stringify(payload);
    return crypto.createHash("sha256").update(raw).digest("hex");
  }

  private async createCachedContent(
    system_instruction: string | undefined,
    tools?: ToolDefinition[] | null
  ): Promise<string | null> {
    if (!this.explicit_context_caching) return null;
    if (!system_instruction && (!tools || !tools.length)) return null;
    if (this.include_system_in_user) return null;

    const cacheKey = this.buildCacheKey(system_instruction, tools);
    if (this.cachedContentKey === cacheKey && this.cachedContentName) {
      return this.cachedContentName;
    }

    try {
      const body: Record<string, unknown> = {
        model: this.model,
      };
      if (system_instruction) {
        body.systemInstruction = { parts: [{ text: system_instruction }] };
      }
      if (tools && tools.length) {
        body.tools = this.serializeTools(tools);
      }
      if (this.explicit_cache_ttl_seconds) {
        body.ttl = `${this.explicit_cache_ttl_seconds}s`;
      }

      const response = await fetch(
        `${this.base_url}/cachedContents?key=${encodeURIComponent(this.api_key ?? "")}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        }
      );

      if (!response.ok) return null;
      const data = await response.json();
      const name = data?.name ?? data?.id ?? null;
      if (name) {
        this.cachedContentName = name;
        this.cachedContentKey = cacheKey;
      }
      return name;
    } catch {
      return null;
    }
  }

  private serializeTools(tools: ToolDefinition[]): any[] {
    const functionDeclarations = tools.map((tool) => ({
      name: tool.name,
      description: tool.description,
      parameters: this.fixGeminiSchema(tool.parameters as Record<string, unknown>),
    }));
    return [{ functionDeclarations }];
  }

  private getToolChoice(tool_choice: ToolChoice | null | undefined, tools?: ToolDefinition[] | null): any {
    if (!tool_choice || !tools || !tools.length) return null;
    if (tool_choice === "auto") {
      return { functionCallingConfig: { mode: "AUTO" } };
    }
    if (tool_choice === "required") {
      return { functionCallingConfig: { mode: "ANY" } };
    }
    if (tool_choice === "none") {
      return { functionCallingConfig: { mode: "NONE" } };
    }
    return { functionCallingConfig: { mode: "ANY", allowedFunctionNames: [tool_choice] } };
  }

  private extractToolCalls(response: any): ToolCall[] {
    const toolCalls: ToolCall[] = [];
    const parts = response?.candidates?.[0]?.content?.parts ?? [];
    for (const part of parts) {
      if (part?.functionCall) {
        const fc = part.functionCall;
        const args = fc.args ? JSON.stringify(fc.args) : "{}";
        const tool_call_id = fc.id || `call_${crypto.randomBytes(12).toString("hex")}`;
        toolCalls.push({
          id: tool_call_id,
          type: "function",
          function: { name: fc.name, arguments: args },
          thought_signature: part.thoughtSignature ?? null,
        });
      }
    }
    return toolCalls;
  }

  private extractText(response: any): string | null {
    const parts = response?.candidates?.[0]?.content?.parts ?? [];
    const texts = parts
      .filter((p: any) => typeof p.text === "string")
      .map((p: any) => p.text);
    return texts.length ? texts.join("\n") : null;
  }

  private extractUsage(response: any): ChatInvokeUsage | null {
    const usage = response?.usageMetadata;
    if (!usage) return null;

    let imageTokens = 0;
    const details = usage.promptTokensDetails ?? [];
    for (const detail of details) {
      if (detail.modality === "IMAGE") {
        imageTokens += detail.tokenCount ?? 0;
      }
    }

    return {
      prompt_tokens: usage.promptTokenCount ?? 0,
      completion_tokens: (usage.candidatesTokenCount ?? 0) + (usage.thoughtsTokenCount ?? 0),
      total_tokens: usage.totalTokenCount ?? 0,
      prompt_cached_tokens: usage.cachedContentTokenCount ?? null,
      prompt_cache_creation_tokens: null,
      prompt_image_tokens: imageTokens,
    };
  }

  private fixGeminiSchema(schema: Record<string, any>): Record<string, any> {
    const result = JSON.parse(JSON.stringify(schema));
    if (result.$defs) {
      const defs = result.$defs;
      delete result.$defs;
      const resolveRefs = (obj: any): any => {
        if (Array.isArray(obj)) return obj.map(resolveRefs);
        if (!obj || typeof obj !== "object") return obj;
        if (obj.$ref) {
          const refName = obj.$ref.split("/").pop();
          if (refName && defs[refName]) {
            const merged = { ...defs[refName], ...obj };
            delete merged.$ref;
            return resolveRefs(merged);
          }
        }
        const out: any = {};
        for (const [key, value] of Object.entries(obj)) {
          out[key] = resolveRefs(value);
        }
        return out;
      };
      return this.cleanSchema(resolveRefs(result));
    }
    return this.cleanSchema(result);
  }

  private cleanSchema(obj: any, parentKey?: string): any {
    if (Array.isArray(obj)) return obj.map((item) => this.cleanSchema(item, parentKey));
    if (!obj || typeof obj !== "object") return obj;

    const cleaned: any = {};
    for (const [key, value] of Object.entries(obj)) {
      const isMetadataTitle = key === "title" && parentKey !== "properties";
      if (key === "additionalProperties" || key === "default" || isMetadataTitle) {
        continue;
      }
      cleaned[key] = this.cleanSchema(value, key);
    }

    if (
      typeof cleaned.type === "string" &&
      cleaned.type.toUpperCase() === "OBJECT" &&
      cleaned.properties &&
      typeof cleaned.properties === "object" &&
      Object.keys(cleaned.properties).length === 0
    ) {
      cleaned.properties = { _placeholder: { type: "string" } };
    }

    return cleaned;
  }

  async ainvoke(
    messages: AnyMessage[],
    tools?: ToolDefinition[] | null,
    tool_choice?: ToolChoice | null,
    extra?: Record<string, unknown>
  ): Promise<ChatInvokeCompletion> {
    if (!this.api_key) {
      throw new ModelProviderError(
        "GOOGLE_API_KEY is required",
        401,
        this.name
      );
    }

    const { contents, system_instruction } = GoogleMessageSerializer.serializeMessages(
      messages,
      this.include_system_in_user
    );

    const config: Record<string, any> = { ...(this.config ?? {}) };
    if (this.temperature !== null) config.temperature = this.temperature;
    if (this.top_p !== null) config.topP = this.top_p;
    if (this.seed !== null) config.seed = this.seed;
    if (this.max_output_tokens !== null) config.maxOutputTokens = this.max_output_tokens;

    if (this.thinking_budget !== null) {
      config.thinkingConfig = { thinkingBudget: this.thinking_budget };
    } else if (this.thinking_budget === null && this.model.includes("gemini-2.5-flash")) {
      config.thinkingConfig = { thinkingBudget: 0 };
    }

    const cachedContent = await this.createCachedContent(system_instruction, tools);

    const body: Record<string, unknown> = {
      contents,
      generationConfig: config,
    };

    if (cachedContent) {
      body.cachedContent = cachedContent;
    } else if (system_instruction) {
      body.systemInstruction = { parts: [{ text: system_instruction }] };
    }

    if (tools && tools.length && !cachedContent) {
      body.tools = this.serializeTools(tools);
    }

    const toolConfig = this.getToolChoice(tool_choice ?? "auto", tools);
    if (toolConfig) body.toolConfig = toolConfig;

    Object.assign(body, extra ?? {});

    const makeRequest = async (): Promise<ChatInvokeCompletion> => {
      const response = await fetch(
        `${this.base_url}/models/${encodeURIComponent(this.model)}:generateContent?key=${encodeURIComponent(
          this.api_key ?? ""
        )}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        }
      );

      if (!response.ok) {
        const text = await response.text();
        throw new ModelProviderError(
          text || `Gemini error (${response.status})`,
          response.status,
          this.name
        );
      }

      const data = await response.json();
      const content = this.extractText(data);
      const toolCalls = this.extractToolCalls(data);
      const usage = this.extractUsage(data);
      const stopReason = data?.candidates?.[0]?.finishReason ?? null;

      return { content, tool_calls: toolCalls, usage, stop_reason: stopReason };
    };

    for (let attempt = 0; attempt < this.max_retries; attempt += 1) {
      try {
        return await makeRequest();
      } catch (err: any) {
        const status = err?.status_code ?? err?.status ?? err?.response?.status ?? null;
        const retryable = status && this.retryable_status_codes.includes(status);
        if (retryable && attempt < this.max_retries - 1) {
          const delay = Math.min(this.retry_base_delay * 2 ** attempt, this.retry_max_delay);
          const jitter = Math.random() * delay * 0.1;
          const totalDelay = delay + jitter;
          await new Promise((r) => setTimeout(r, totalDelay * 1000));
          continue;
        }
        if (err instanceof ModelProviderError) throw err;
        throw new ModelProviderError(String(err?.message ?? err), status ?? 502, this.name);
      }
    }

    throw new Error("Retry loop completed without return or exception");
  }
}
