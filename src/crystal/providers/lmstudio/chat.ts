import { ChatOpenAILike, type ChatOpenAILikeOptions } from "../openai/like";

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

