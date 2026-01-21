import { ChatOpenAI, type ChatOpenAIOptions } from "./chat";

export class ChatOpenAILike extends ChatOpenAI {
  constructor(options: ChatOpenAIOptions) {
    super(options);
  }
}
