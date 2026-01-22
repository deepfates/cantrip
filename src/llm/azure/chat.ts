import { ChatOpenAILike } from "../openai/like";
import type { ChatOpenAIOptions } from "../openai/chat";

import { OpenAIMessageSerializer } from "../openai/serializer";
import { ModelProviderError, ModelRateLimitError } from "../exceptions";
import type { ToolChoice, ToolDefinition } from "../base";
import type { ToolCall } from "../messages";
import type { ChatInvokeCompletion, ChatInvokeUsage } from "../views";

export type ChatAzureOpenAIOptions = ChatOpenAIOptions & {
  azure_endpoint?: string | null;
  azure_deployment?: string | null;
  api_version?: string | null;
};

export class ChatAzureOpenAI extends ChatOpenAILike {
  private apiVersion: string;
  private deployment: string;
  private endpoint: string;

  constructor(options: ChatAzureOpenAIOptions) {
    const endpoint =
      options.azure_endpoint ??
      options.base_url ??
      process.env.AZURE_OPENAI_ENDPOINT ??
      process.env.AZURE_OPENAI_BASE_URL ??
      "";

    super({
      ...options,
      base_url: endpoint || options.base_url,
      api_key:
        options.api_key ??
        process.env.AZURE_OPENAI_API_KEY ??
        process.env.AZURE_OPENAI_KEY ??
        null,
      providerName: "azure",
    } as any);

    this.apiVersion =
      options.api_version ??
      process.env.AZURE_OPENAI_API_VERSION ??
      "2024-10-21";
    this.deployment = options.azure_deployment ?? options.model ?? "";
    this.endpoint = endpoint;
  }

  private getBaseUrl(): string {
    const base = this.endpoint.replace(/\/$/, "");
    return `${base}/openai/deployments/${this.deployment}`;
  }

  async ainvoke(
    messages: any[],
    tools?: ToolDefinition[] | null,
    tool_choice?: ToolChoice | null,
    extra?: Record<string, unknown>,
  ): Promise<ChatInvokeCompletion> {
    if (!this.api_key) {
      throw new ModelProviderError(
        "AZURE_OPENAI_API_KEY is required",
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

    if (tools && tools.length) {
      modelParams.tools = this.serializeAzureTools(tools);
      const mappedChoice = this.getAzureToolChoice(tool_choice ?? "auto", tools);
      if (mappedChoice !== null) modelParams.tool_choice = mappedChoice;
    }

    const body = {
      messages: openaiMessages,
      ...modelParams,
      ...(extra ?? {}),
    };

    const url = `${this.getBaseUrl()}/chat/completions?api-version=${encodeURIComponent(
      this.apiVersion,
    )}`;

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "api-key": this.api_key,
      },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const text = await response.text();
      if (response.status === 429) {
        throw new ModelRateLimitError(text || "Rate limited", 429, this.name);
      }
      throw new ModelProviderError(
        text || `Azure OpenAI error (${response.status})`,
        response.status,
        this.name,
      );
    }

    const data = await response.json();
    return this.toAzureCompletion(data);
  }

  private serializeAzureTools(
    tools: ToolDefinition[],
  ): Array<Record<string, any>> {
    return tools.map((tool) => ({
      type: "function",
      function: {
        name: tool.name,
        description: tool.description,
        parameters: tool.parameters,
        strict: tool.strict ?? true,
      },
    }));
  }

  private getAzureToolChoice(
    tool_choice: ToolChoice | null | undefined,
    tools: ToolDefinition[],
  ): any {
    if (!tool_choice || !tools) return null;
    if (tool_choice === "auto") return "auto";
    if (tool_choice === "required") return "required";
    if (tool_choice === "none") return "none";
    return { type: "function", function: { name: tool_choice } };
  }

  private extractAzureToolCalls(response: any): ToolCall[] {
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

  private extractAzureUsage(response: any): ChatInvokeUsage | null {
    if (!response?.usage) return null;
    return {
      prompt_tokens: response.usage.prompt_tokens ?? 0,
      prompt_cached_tokens:
        response.usage.prompt_tokens_details?.cached_tokens ?? null,
      prompt_cache_creation_tokens: null,
      prompt_image_tokens: null,
      completion_tokens: response.usage.completion_tokens ?? 0,
      total_tokens: response.usage.total_tokens ?? 0,
    };
  }

  private toAzureCompletion(response: any): ChatInvokeCompletion {
    const content = response?.choices?.[0]?.message?.content ?? null;
    const toolCalls = this.extractAzureToolCalls(response);
    const usage = this.extractAzureUsage(response);
    return {
      content,
      tool_calls: toolCalls,
      usage,
      stop_reason: response?.choices?.[0]?.finish_reason ?? null,
    };
  }
}
