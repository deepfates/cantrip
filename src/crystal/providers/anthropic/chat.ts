import type { AnyMessage, GateCall } from "../../messages";
import type { BaseChatModel, ToolChoice, GateDefinition } from "../../crystal";
import { ModelProviderError, ModelRateLimitError } from "../../exceptions";
import type { ChatInvokeCompletion, ChatInvokeUsage } from "../../views";
import { AnthropicMessageSerializer } from "./serializer";

export type ChatAnthropicOptions = {
  model: string;
  max_tokens?: number;
  temperature?: number | null;
  top_p?: number | null;
  seed?: number | null;
  api_key?: string | null;
  base_url?: string | null;
  prompt_cache_beta?: string | null;
  max_cached_tool_definitions?: number;
  context_window?: number;
};

export class ChatAnthropic implements BaseChatModel {
  model: string;
  max_tokens: number;
  temperature: number | null;
  top_p: number | null;
  seed: number | null;
  api_key: string | null;
  base_url: string;
  prompt_cache_beta: string | null;
  max_cached_tool_definitions: number;
  context_window: number;

  constructor(options: ChatAnthropicOptions) {
    this.model = options.model;
    this.max_tokens = options.max_tokens ?? 8192;
    this.temperature = options.temperature ?? null;
    this.top_p = options.top_p ?? null;
    this.seed = options.seed ?? null;
    this.api_key = options.api_key ?? process.env.ANTHROPIC_API_KEY ?? null;
    this.base_url = options.base_url ?? "https://api.anthropic.com";
    this.prompt_cache_beta =
      options.prompt_cache_beta ?? "prompt-caching-2024-07-31";
    this.max_cached_tool_definitions =
      options.max_cached_tool_definitions ?? 3;
    this.context_window = options.context_window ?? 200_000;
  }

  get provider(): string {
    return "anthropic";
  }

  get name(): string {
    return String(this.model);
  }

  private serializeTools(tools: GateDefinition[]): any[] {
    const result: any[] = [];
    const cacheCount = Math.max(this.max_cached_tool_definitions, 0);
    const cacheStart = Math.max(tools.length - cacheCount, 0);

    tools.forEach((tool, index) => {
      const schema = { ...(tool.parameters as Record<string, unknown>) } as any;
      if (schema.title) delete schema.title;
      const toolParam: any = {
        name: tool.name,
        description: tool.description,
        input_schema: schema,
      };
      if (index >= cacheStart) {
        toolParam.cache_control = { type: "ephemeral" };
      }
      result.push(toolParam);
    });

    return result;
  }

  private getToolChoice(
    tool_choice: ToolChoice | null | undefined,
    tools: GateDefinition[] | null | undefined
  ): any {
    if (!tool_choice || !tools) return null;
    if (tool_choice === "auto") return { type: "auto" };
    if (tool_choice === "required") return { type: "any" };
    if (tool_choice === "none") return { type: "none" };
    // Handle object format: { type: string, name: string }
    if (typeof tool_choice === "object" && "name" in tool_choice) {
      return { type: "tool", name: tool_choice.name };
    }
    return { type: "tool", name: tool_choice };
  }

  private extractGateCalls(response: any): GateCall[] {
    const toolCalls: GateCall[] = [];
    const blocks = response?.content ?? [];
    for (const block of blocks) {
      if (block?.type === "tool_use") {
        const args =
          typeof block.input === "object"
            ? JSON.stringify(block.input)
            : String(block.input ?? "{}");
        toolCalls.push({
          id: block.id,
          type: "function",
          function: { name: block.name, arguments: args },
        });
      }
    }
    return toolCalls;
  }

  private extractText(response: any): string | null {
    const blocks = response?.content ?? [];
    const texts = blocks
      .filter((b: any) => b?.type === "text")
      .map((b: any) => b.text);
    return texts.length ? texts.join("\n") : null;
  }

  private extractThinking(response: any): { thinking: string | null; redacted: string | null } {
    const blocks = response?.content ?? [];
    const thinkingParts: string[] = [];
    const redactedParts: string[] = [];
    for (const block of blocks) {
      if (block?.type === "thinking") thinkingParts.push(block.thinking);
      if (block?.type === "redacted_thinking") redactedParts.push(block.data);
    }
    return {
      thinking: thinkingParts.length ? thinkingParts.join("\n") : null,
      redacted: redactedParts.length ? redactedParts.join("\n") : null,
    };
  }

  private extractUsage(response: any): ChatInvokeUsage | null {
    const usage = response?.usage;
    if (!usage) return null;
    const cacheRead = usage.cache_read_input_tokens ?? 0;
    return {
      prompt_tokens: (usage.input_tokens ?? 0) + cacheRead,
      completion_tokens: usage.output_tokens ?? 0,
      total_tokens: (usage.input_tokens ?? 0) + (usage.output_tokens ?? 0),
      prompt_cached_tokens: usage.cache_read_input_tokens ?? null,
      prompt_cache_creation_tokens: usage.cache_creation_input_tokens ?? null,
      prompt_image_tokens: null,
    };
  }

  async ainvoke(
    messages: AnyMessage[],
    tools?: GateDefinition[] | null,
    tool_choice?: ToolChoice | null,
    extra?: Record<string, unknown>
  ): Promise<ChatInvokeCompletion> {
    if (!this.api_key) {
      throw new ModelProviderError(
        "ANTHROPIC_API_KEY is required",
        401,
        this.name
      );
    }

    const { messages: serializedMessages, system } =
      AnthropicMessageSerializer.serializeMessages(messages);

    const body: Record<string, unknown> = {
      model: this.model,
      messages: serializedMessages,
      max_tokens: this.max_tokens,
    };

    if (this.temperature !== null) body.temperature = this.temperature;
    if (this.top_p !== null) body.top_p = this.top_p;
    if (this.seed !== null) body.seed = this.seed;
    if (system) body.system = system;

    if (tools && tools.length) {
      body.tools = this.serializeTools(tools);
      const choice = this.getToolChoice(tool_choice ?? "auto", tools);
      if (choice) body.tool_choice = choice;
    }

    Object.assign(body, extra ?? {});

    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      "x-api-key": this.api_key,
      "anthropic-version": "2023-06-01",
    };

    if (this.prompt_cache_beta) {
      headers["anthropic-beta"] = this.prompt_cache_beta;
    }

    const response = await fetch(`${this.base_url}/v1/messages`, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const text = await response.text();
      if (response.status === 429) {
        throw new ModelRateLimitError(text || "Rate limited", 429, this.name);
      }
      throw new ModelProviderError(
        text || `Anthropic error (${response.status})`,
        response.status,
        this.name
      );
    }

    const data = await response.json();

    const content = this.extractText(data);
    const toolCalls = this.extractGateCalls(data);
    const { thinking, redacted } = this.extractThinking(data);
    const usage = this.extractUsage(data);

    return {
      content,
      tool_calls: toolCalls,
      thinking,
      redacted_thinking: redacted,
      usage,
      stop_reason: data?.stop_reason ?? null,
    };
  }
}
