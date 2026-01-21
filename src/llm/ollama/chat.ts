import { ChatOpenAILike } from "../openai/like";
import type { ChatOpenAIOptions } from "../openai/chat";

export class ChatOllama extends ChatOpenAILike {
  constructor(options: ChatOpenAIOptions) {
    super({
      ...options,
      base_url: options.base_url ?? process.env.OLLAMA_BASE_URL ?? "http://localhost:11434/v1",
      api_key: options.api_key ?? process.env.OLLAMA_API_KEY ?? null,
      providerName: "ollama",
    } as any);
  }
}
