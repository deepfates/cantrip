import { ChatOpenAILike } from "../openai/like";
import type { ChatOpenAIOptions } from "../openai/chat";

export class ChatCerebras extends ChatOpenAILike {
  constructor(options: ChatOpenAIOptions) {
    super({
      ...options,
      base_url: options.base_url ?? process.env.CEREBRAS_BASE_URL ?? "https://api.cerebras.ai/v1",
      api_key: options.api_key ?? process.env.CEREBRAS_API_KEY ?? null,
      providerName: "cerebras",
    } as any);
  }
}
