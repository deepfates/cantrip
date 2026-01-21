import { ChatOpenAILike } from "../openai/like";
import type { ChatOpenAIOptions } from "../openai/chat";

export class ChatGroq extends ChatOpenAILike {
  constructor(options: ChatOpenAIOptions) {
    super({
      ...options,
      base_url: options.base_url ?? process.env.GROQ_BASE_URL ?? "https://api.groq.com/openai/v1",
      api_key: options.api_key ?? process.env.GROQ_API_KEY ?? null,
      providerName: "groq",
    } as any);
  }
}
