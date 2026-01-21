import type { AnyMessage, ToolCall } from "../messages";
import type { BaseChatModel, ToolChoice, ToolDefinition } from "../base";
import { ModelProviderError, ModelRateLimitError } from "../exceptions";
import type { ChatInvokeCompletion, ChatInvokeUsage } from "../views";
import { OpenAIMessageSerializer } from "./serializer";

export type ReasoningEffort = "low" | "medium" | "high";
export type ServiceTier = "auto" | "default" | "flex" | "priority" | "scale";

export type ChatOpenAIOptions = {
  model: string;
  api_key?: string | null;
  base_url?: string | null;
  temperature?: number | null;
  frequency_penalty?: number | null;
  reasoning_effort?: ReasoningEffort;
  seed?: number | null;
  service_tier?: ServiceTier | null;
  top_p?: number | null;
  parallel_tool_calls?: boolean;
  prompt_cache_key?: string | null;
  prompt_cache_retention?: "in_memory" | "24h" | null;
  extended_cache_models?: string[];
  max_completion_tokens?: number | null;
  reasoning_models?: string[];
};

export class ChatOpenAI implements BaseChatModel {
  model: string;
  temperature: number | null;
  frequency_penalty: number | null;
  reasoning_effort: ReasoningEffort;
  seed: number | null;
  service_tier: ServiceTier | null;
  top_p: number | null;
  parallel_tool_calls: boolean;
  prompt_cache_key: string | null;
  prompt_cache_retention: "in_memory" | "24h" | null;
  extended_cache_models: string[];
  api_key: string | null;
  base_url: string;
  max_completion_tokens: number | null;
  reasoning_models: string[];

  constructor(options: ChatOpenAIOptions) {
    this.model = options.model;
    this.temperature = options.temperature ?? 0.2;
    this.frequency_penalty = options.frequency_penalty ?? 0.3;
    this.reasoning_effort = options.reasoning_effort ?? "low";
    this.seed = options.seed ?? null;
    this.service_tier = options.service_tier ?? null;
    this.top_p = options.top_p ?? null;
    this.parallel_tool_calls = options.parallel_tool_calls ?? true;
    this.prompt_cache_key = options.prompt_cache_key ?? "bu_agent_sdk-agent";
    this.prompt_cache_retention = options.prompt_cache_retention ?? null;
    this.extended_cache_models =
      options.extended_cache_models ??
      [
        "gpt-5.2",
        "gpt-5.1-codex-max",
        "gpt-5.1",
        "gpt-5.1-codex",
        "gpt-5.1-codex-mini",
        "gpt-5.1-chat-latest",
        "gpt-5",
        "gpt-5-codex",
        "gpt-4.1",
      ];
    this.api_key = options.api_key ?? process.env.OPENAI_API_KEY ?? null;
    this.base_url = options.base_url ?? "https://api.openai.com/v1";
    this.max_completion_tokens = options.max_completion_tokens ?? 4096;
    this.reasoning_models = options.reasoning_models ?? [
      "o4-mini",
      "o3",
      "o3-mini",
      "o1",
      "o1-pro",
      "o3-pro",
      "gpt-5",
      "gpt-5-mini",
      "gpt-5-nano",
    ];
  }

  get provider(): string {
    return "openai";
  }

  get name(): string {
    return String(this.model);
  }

  private resolvePromptCacheRetention(): "in_memory" | "24h" | null {
    if (this.prompt_cache_retention !== null) return this.prompt_cache_retention;
    const modelName = String(this.model).toLowerCase();
    if (this.extended_cache_models.some((m) => modelName.includes(m))) {
      return "24h";
    }
    return null;
  }

  private makeStrictSchema(schema: Record<string, unknown>): Record<string, unknown> {
    const copy = JSON.parse(JSON.stringify(schema)) as Record<string, any>;
    const props = (copy.properties ?? {}) as Record<string, any>;
    const required = new Set((copy.required ?? []) as string[]);

    const newProps: Record<string, any> = {};
    for (const [name, prop] of Object.entries(props)) {
      newProps[name] = this.makeStrictProperty(prop, required.has(name));
    }

    copy.properties = newProps;
    copy.required = Object.keys(props);
    copy.additionalProperties = false;
    return copy;
  }

  private makeStrictProperty(prop: Record<string, any>, isRequired: boolean) {
    const copy = JSON.parse(JSON.stringify(prop)) as Record<string, any>;

    if (copy.type === "object" && copy.properties) {
      return this.makeStrictSchema(copy);
    }
    if (copy.type === "array" && copy.items && copy.items.type === "object") {
      copy.items = this.makeStrictSchema(copy.items);
    }

    if (!isRequired) {
      if (copy.type) {
        copy.type = Array.isArray(copy.type) ? copy.type : [copy.type, "null"];
      } else if (!copy.anyOf) {
        copy.anyOf = [copy, { type: "null" }];
      }
    }

    return copy;
  }

  private serializeTools(tools: ToolDefinition[]): Array<Record<string, unknown>> {
    return tools.map((tool) => {
      const params = tool.strict
        ? this.makeStrictSchema(tool.parameters as Record<string, unknown>)
        : tool.parameters;
      return {
        type: "function",
        function: {
          name: tool.name,
          description: tool.description,
          parameters: params,
          strict: tool.strict ?? true,
        },
      };
    });
  }

  private getToolChoice(
    tool_choice: ToolChoice | null | undefined,
    tools: ToolDefinition[] | null | undefined
  ): unknown {
    if (!tool_choice || !tools) return null;
    if (tool_choice === "auto") return "auto";
    if (tool_choice === "required") return "required";
    if (tool_choice === "none") return "none";
    return { type: "function", function: { name: tool_choice } };
  }

  private extractToolCalls(response: any): ToolCall[] {
    const message = response?.choices?.[0]?.message;
    if (!message?.tool_calls) return [];
    return message.tool_calls.map((tc: any) => ({
      id: tc.id,
      type: "function",
      function: {
        name: tc.function?.name,
        arguments: tc.function?.arguments ?? "{}",
      },
    }));
  }

  private extractUsage(response: any): ChatInvokeUsage | null {
    if (!response?.usage) return null;
    let completionTokens = response.usage.completion_tokens ?? 0;
    const details = response.usage.completion_tokens_details;
    if (details?.reasoning_tokens) completionTokens += details.reasoning_tokens;

    return {
      prompt_tokens: response.usage.prompt_tokens ?? 0,
      prompt_cached_tokens:
        response.usage.prompt_tokens_details?.cached_tokens ?? null,
      prompt_cache_creation_tokens: null,
      prompt_image_tokens: null,
      completion_tokens: completionTokens,
      total_tokens: response.usage.total_tokens ?? 0,
    };
  }

  async ainvoke(
    messages: AnyMessage[],
    tools?: ToolDefinition[] | null,
    tool_choice?: ToolChoice | null,
    extra?: Record<string, unknown>
  ): Promise<ChatInvokeCompletion> {
    if (!this.api_key) {
      throw new ModelProviderError(
        "OPENAI_API_KEY is required",
        401,
        this.name
      );
    }

    const openaiMessages = OpenAIMessageSerializer.serializeMessages(messages);

    const modelParams: Record<string, unknown> = {};
    if (this.temperature !== null) modelParams.temperature = this.temperature;
    if (this.frequency_penalty !== null)
      modelParams.frequency_penalty = this.frequency_penalty;
    if (this.max_completion_tokens !== null)
      modelParams.max_completion_tokens = this.max_completion_tokens;
    if (this.top_p !== null) modelParams.top_p = this.top_p;
    if (this.seed !== null) modelParams.seed = this.seed;
    if (this.service_tier !== null) modelParams.service_tier = this.service_tier;

    const extraBody: Record<string, unknown> = {};
    if (this.prompt_cache_key) extraBody.prompt_cache_key = this.prompt_cache_key;
    const retention = this.resolvePromptCacheRetention();
    if (retention) extraBody.prompt_cache_retention = retention;
    if (Object.keys(extraBody).length) modelParams.extra_body = extraBody;

    const isReasoningModel = this.reasoning_models.some((m) =>
      String(this.model).toLowerCase().includes(m)
    );
    if (isReasoningModel) {
      modelParams.reasoning_effort = this.reasoning_effort;
      delete modelParams.temperature;
      delete modelParams.frequency_penalty;
    }

    if (tools && tools.length) {
      modelParams.tools = this.serializeTools(tools);
      modelParams.parallel_tool_calls = this.parallel_tool_calls;
      const mappedChoice = this.getToolChoice(tool_choice ?? "auto", tools);
      if (mappedChoice !== null) modelParams.tool_choice = mappedChoice;
    }

    const body = {
      model: this.model,
      messages: openaiMessages,
      ...modelParams,
      ...(extra ?? {}),
    };

    const response = await fetch(`${this.base_url}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.api_key}`,
      },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const text = await response.text();
      if (response.status === 429) {
        throw new ModelRateLimitError(text || "Rate limited", 429, this.name);
      }
      throw new ModelProviderError(
        text || `OpenAI error (${response.status})`,
        response.status,
        this.name
      );
    }

    const data = await response.json();

    const content = data?.choices?.[0]?.message?.content ?? null;
    const toolCalls = this.extractToolCalls(data);
    const usage = this.extractUsage(data);

    return {
      content,
      tool_calls: toolCalls,
      usage,
      stop_reason: data?.choices?.[0]?.finish_reason ?? null,
    };
  }
}
