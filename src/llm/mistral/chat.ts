import { ChatOpenAILike } from "../openai/like";
import type { ChatOpenAIOptions } from "../openai/chat";

export class ChatMistral extends ChatOpenAILike {
  constructor(options: ChatOpenAIOptions) {
    super({
      ...options,
      base_url: options.base_url ?? process.env.MISTRAL_BASE_URL ?? "https://api.mistral.ai/v1",
      api_key: options.api_key ?? process.env.MISTRAL_API_KEY ?? null,
      providerName: "mistral",
    } as any);
  }
}
