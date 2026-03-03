import { ChatOpenAILike, type ChatOpenAILikeOptions } from "../openai/like";
import type { AnyMessage } from "../messages";
import type { ToolChoice, ToolDefinition } from "../base";
import type { ChatInvokeCompletion } from "../views";

export type ChatLMStudioOptions = ChatOpenAILikeOptions & {
  /**
   * Override the base URL. Defaults to the LM Studio local server.
   */
  base_url?: string | null;
};

/**
 * LM Studio runs a local OpenAI-compatible server (default: http://localhost:1234/v1).
 * It often doesn't require an API key, so we disable the requirement by default.
 */
export class ChatLMStudio extends ChatOpenAILike {
  async query(
    messages: AnyMessage[],
    tools?: ToolDefinition[] | null,
    tool_choice?: ToolChoice | null,
    extra?: Record<string, unknown>,
  ): Promise<ChatInvokeCompletion> {
    return this.ainvoke(messages, tools, tool_choice, extra);
  }

  constructor(options: ChatLMStudioOptions) {
    super({
      ...options,
      providerName: options.providerName ?? "lmstudio",
      base_url: options.base_url ?? "http://localhost:1234/v1",
      api_key: options.api_key ?? process.env.LM_STUDIO_API_KEY ?? null,
      require_api_key: options.require_api_key ?? false,
    });
  }
}
