import { ChatOpenAILike } from "../openai/like";
import type { ChatOpenAIOptions } from "../openai/chat";

export class ChatDeepSeek extends ChatOpenAILike {
  constructor(options: ChatOpenAIOptions) {
    super({
      ...options,
      base_url: options.base_url ?? process.env.DEEPSEEK_BASE_URL ?? "https://api.deepseek.com/v1",
      api_key: options.api_key ?? process.env.DEEPSEEK_API_KEY ?? null,
      providerName: "deepseek",
    } as any);
  }
}
