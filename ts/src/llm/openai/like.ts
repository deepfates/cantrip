import { ChatOpenAI, type ChatOpenAIOptions } from "./chat";

export type ChatOpenAILikeOptions = ChatOpenAIOptions & {
  providerName?: string;
};

export class ChatOpenAILike extends ChatOpenAI {
  private providerName: string;

  constructor(options: ChatOpenAILikeOptions) {
    super(options);
    this.providerName = options.providerName ?? "openai";
  }

  get provider(): string {
    return this.providerName;
  }
}
