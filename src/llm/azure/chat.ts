import { ChatOpenAILike } from "../openai/like";
import type { ChatOpenAIOptions } from "../openai/chat";

export type ChatAzureOpenAIOptions = ChatOpenAIOptions & {
  azure_endpoint?: string | null;
};

export class ChatAzureOpenAI extends ChatOpenAILike {
  constructor(options: ChatAzureOpenAIOptions) {
    const base_url =
      options.azure_endpoint ??
      options.base_url ??
      process.env.AZURE_OPENAI_ENDPOINT ??
      process.env.AZURE_OPENAI_BASE_URL ??
      "";

    super({
      ...options,
      base_url: base_url || options.base_url,
      api_key:
        options.api_key ??
        process.env.AZURE_OPENAI_API_KEY ??
        process.env.AZURE_OPENAI_KEY ??
        null,
      providerName: "azure",
    } as any);
  }
}
