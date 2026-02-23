import { ChatOpenAILike, type ChatOpenAILikeOptions } from "../openai/like";
import type { GateDefinition, ToolChoice } from "../../crystal";

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
 * OpenRouter exposes an OpenAI-compatible API that routes to many providers.
 *
 * Unlike direct OpenAI, we must avoid provider-specific fields that break
 * when OpenRouter routes to non-OpenAI backends (Anthropic, Google, etc.):
 * - No `parallel_tool_calls` (OpenAI-only; Anthropic rejects it)
 * - No `strict` on tool functions (OpenAI-only)
 * - tool_choice uses OpenAI format (OpenRouter translates for us)
 */
export class ChatOpenRouter extends ChatOpenAILike {
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

  /** Strip `strict` from tool functions — not all providers support it. */
  protected override serializeTools(
    tools: GateDefinition[],
  ): Array<Record<string, unknown>> {
    return tools.map((tool) => ({
      type: "function",
      function: {
        name: tool.name,
        description: tool.description,
        parameters: tool.parameters,
      },
    }));
  }

  /** Don't send `parallel_tool_calls` — it's OpenAI-specific and breaks Anthropic routing. */
  protected override applyToolParams(
    modelParams: Record<string, unknown>,
    tool_choice: ToolChoice,
    tools: GateDefinition[],
  ): void {
    const mappedChoice = this.getToolChoice(tool_choice, tools);
    if (mappedChoice !== null) modelParams.tool_choice = mappedChoice;
  }
}
