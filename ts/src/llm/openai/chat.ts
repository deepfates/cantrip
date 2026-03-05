import type { AnyMessage, ToolCall } from "../messages";
import type { BaseChatModel, ToolChoice, ToolDefinition } from "../base";
import { ModelProviderError, ModelRateLimitError } from "../exceptions";
import type { ChatInvokeCompletion, ChatInvokeUsage } from "../views";
import { OpenAIMessageSerializer } from "./serializer";

export type ReasoningEffort = "low" | "medium" | "high";
export type ServiceTier = "auto" | "default" | "flex" | "priority";

export type ChatOpenAIOptions = {
  model: string;
  api_key?: string | null;
  base_url?: string | null;
  headers?: Record<string, string> | null;
  require_api_key?: boolean;
  temperature?: number | null;
  frequency_penalty?: number | null;
  /** Whether this is a reasoning model (sends reasoning_effort instead of temperature/frequency_penalty). */
  reasoning?: boolean;
  reasoning_effort?: ReasoningEffort;
  seed?: number | null;
  service_tier?: ServiceTier | null;
  top_p?: number | null;
  parallel_tool_calls?: boolean;
  max_completion_tokens?: number | null;
};

export class ChatOpenAI implements BaseChatModel {
  model: string;
  temperature: number | null;
  frequency_penalty: number | null;
  reasoning: boolean;
  reasoning_effort: ReasoningEffort;
  seed: number | null;
  service_tier: ServiceTier | null;
  top_p: number | null;
  parallel_tool_calls: boolean;
  api_key: string | null;
  base_url: string;
  headers: Record<string, string>;
  require_api_key: boolean;
  max_completion_tokens: number | null;

  constructor(options: ChatOpenAIOptions) {
    this.model = options.model;
    this.temperature = options.temperature ?? null;
    this.frequency_penalty = options.frequency_penalty ?? null;
    this.reasoning = options.reasoning ?? false;
    this.reasoning_effort = options.reasoning_effort ?? "low";
    this.seed = options.seed ?? null;
    this.service_tier = options.service_tier ?? null;
    this.top_p = options.top_p ?? null;
    this.parallel_tool_calls = options.parallel_tool_calls ?? true;
    const envApiKey = process.env.OPENAI_API_KEY ?? null;
    if (options.api_key === undefined) {
      this.api_key = envApiKey;
    } else if (options.api_key === null && options.require_api_key !== false) {
      this.api_key = envApiKey;
    } else {
      this.api_key = options.api_key;
    }
    this.base_url = options.base_url ?? "https://api.openai.com/v1";
    this.headers = options.headers ?? {};
    this.require_api_key = options.require_api_key ?? true;
    this.max_completion_tokens = options.max_completion_tokens ?? null;
  }

  get provider(): string {
    return "openai";
  }

  get name(): string {
    return String(this.model);
  }

  private makeStrictSchema(
    schema: Record<string, unknown>,
  ): Record<string, unknown> {
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
        const original = JSON.parse(JSON.stringify(copy));
        return { anyOf: [original, { type: "null" }] };
      }
    }

    return copy;
  }

  private serializeTools(
    tools: ToolDefinition[],
  ): Array<Record<string, unknown>> {
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
          strict: tool.strict ?? false,
        },
      };
    });
  }

  private getToolChoice(
    tool_choice: ToolChoice | null | undefined,
    tools: ToolDefinition[] | null | undefined,
  ): unknown {
    if (!tool_choice || !tools) return null;
    if (typeof tool_choice === "object" && tool_choice !== null) {
      const name = (tool_choice as { name?: string }).name;
      if (!name) return null;
      return { type: "function", function: { name } };
    }
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

  async query(
    messages: AnyMessage[],
    tools?: ToolDefinition[] | null,
    tool_choice?: ToolChoice | null,
    extra?: Record<string, unknown>,
  ): Promise<ChatInvokeCompletion> {
    return this.ainvoke(messages, tools, tool_choice, extra);
  }

  async ainvoke(
    messages: AnyMessage[],
    tools?: ToolDefinition[] | null,
    tool_choice?: ToolChoice | null,
    extra?: Record<string, unknown>,
  ): Promise<ChatInvokeCompletion> {
    if (this.require_api_key && !this.api_key) {
      throw new ModelProviderError(
        "OPENAI_API_KEY is required",
        401,
        this.name,
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
    if (this.service_tier !== null)
      modelParams.service_tier = this.service_tier;

    if (this.reasoning) {
      modelParams.reasoning_effort = this.reasoning_effort;
      delete modelParams.temperature;
      delete modelParams.frequency_penalty;
      delete modelParams.top_p;
    }

    if (tools && tools.length) {
      modelParams.tools = this.serializeTools(tools);
      if (!this.reasoning) {
        modelParams.parallel_tool_calls = this.parallel_tool_calls;
      }
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
        ...(this.api_key ? { Authorization: `Bearer ${this.api_key}` } : {}),
        ...this.headers,
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
        this.name,
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
