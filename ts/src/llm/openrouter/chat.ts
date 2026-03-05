import { ChatOpenAILike, type ChatOpenAILikeOptions } from "../openai/like";
import type { AnyMessage } from "../messages";
import type { ToolChoice, ToolDefinition } from "../base";
import type { ChatInvokeCompletion } from "../views";

export type ChatOpenRouterOptions = ChatOpenAILikeOptions & {
  /**
   * Optional HTTP referer to comply with OpenRouter attribution guidelines.
   */
  http_referer?: string | null;
  /**
   * Optional title to display in OpenRouter dashboard.
   */
  x_title?: string | null;
  /**
   * Whether to automatically add attribution headers (default: true).
   */
  attribution_headers?: boolean | null;
};

/**
 * OpenRouter exposes an OpenAI-compatible API with a few header conventions.
 */
export class ChatOpenRouter extends ChatOpenAILike {
  async query(
    messages: AnyMessage[],
    tools?: ToolDefinition[] | null,
    tool_choice?: ToolChoice | null,
    extra?: Record<string, unknown>,
  ): Promise<ChatInvokeCompletion> {
    return this.ainvoke(messages, tools, tool_choice, extra);
  }

  constructor(options: ChatOpenRouterOptions) {
    const wantAttribution = options.attribution_headers ?? true;
    const http_referer =
      options.http_referer ??
      process.env.OPENROUTER_HTTP_REFERER ??
      process.env.OPENROUTER_HTTP_REFERER_URL ??
      null;
    const x_title = options.x_title ?? process.env.OPENROUTER_TITLE ?? null;

    const extraHeaders: Record<string, string> = wantAttribution
      ? {
          ...(http_referer ? { "HTTP-Referer": http_referer } : {}),
          ...(x_title ? { "X-Title": x_title } : {}),
        }
      : {};

    super({
      ...options,
      providerName: options.providerName ?? "openrouter",
      base_url: options.base_url ?? "https://openrouter.ai/api/v1",
      api_key: options.api_key ?? process.env.OPENROUTER_API_KEY ?? null,
      headers: { ...(options.headers ?? {}), ...extraHeaders },
      require_api_key: options.require_api_key ?? true,
    });
  }
}
