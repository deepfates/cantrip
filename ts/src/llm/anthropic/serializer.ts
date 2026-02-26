import type {
  AnyMessage,
  AssistantMessage,
  ContentPartDocument,
  ContentPartImage,
  ContentPartText,
  DeveloperMessage,
  SystemMessage,
  ToolCall,
  ToolMessage,
  UserMessage,
} from "../messages";

export type AnthropicMessageParam = {
  role: "user" | "assistant";
  content: any;
};

type NonSystemMessage = UserMessage | AssistantMessage | ToolMessage;

export class AnthropicMessageSerializer {
  static serializeMessages(
    messages: AnyMessage[]
  ): { messages: AnthropicMessageParam[]; system?: any } {
    const copy = JSON.parse(JSON.stringify(messages)) as AnyMessage[];

    const normalMessages: NonSystemMessage[] = [];
    let systemMessage: SystemMessage | DeveloperMessage | undefined;

    for (const message of copy) {
      if (message.role === "system" || message.role === "developer") {
        systemMessage = message as SystemMessage | DeveloperMessage;
      } else {
        normalMessages.push(message as NonSystemMessage);
      }
    }

    this.cleanCacheMessages(normalMessages);

    const serializedMessages = normalMessages.map((m) =>
      this.serialize(m)
    );

    let serializedSystem: any = undefined;
    if (systemMessage) {
      serializedSystem = this.serializeContentToSystem(systemMessage.content, !!systemMessage.cache);
    }

    return { messages: serializedMessages, system: serializedSystem };
  }

  static serialize(message: NonSystemMessage): AnthropicMessageParam {
    if (message.role === "user") {
      return {
        role: "user",
        content: this.serializeContent(message.content, !!message.cache),
      };
    }

    if (message.role === "tool") {
      const toolResult = this.serializeToolMessage(message, !!message.cache);
      return { role: "user", content: [toolResult] };
    }

    // assistant
    return { role: "assistant", content: this.serializeAssistantContent(message) };
  }

  private static serializeContentToSystem(
    content: string | ContentPartText[],
    use_cache: boolean
  ): any {
    const cacheControl = use_cache ? { type: "ephemeral" } : undefined;

    if (typeof content === "string") {
      if (cacheControl) return [{ type: "text", text: content, cache_control: cacheControl }];
      return content;
    }

    return content
      .filter((p) => p.type === "text")
      .map((p, i) => ({
        type: "text",
        text: p.text,
        ...(use_cache && i === content.length - 1 ? { cache_control: cacheControl } : {}),
      }));
  }

  private static serializeContent(
    content: string | (ContentPartText | ContentPartImage | ContentPartDocument)[],
    use_cache: boolean
  ): any {
    const cacheControl = use_cache ? { type: "ephemeral" } : undefined;
    if (typeof content === "string") {
      if (cacheControl) return [{ type: "text", text: content, cache_control: cacheControl }];
      return content;
    }

    const blocks: any[] = [];
    for (let i = 0; i < content.length; i += 1) {
      const part = content[i];
      const isLast = i === content.length - 1;
      if (part.type === "text") {
        blocks.push({
          type: "text",
          text: part.text,
          ...(use_cache && isLast ? { cache_control: cacheControl } : {}),
        });
      } else if (part.type === "image_url") {
        blocks.push(this.serializeImage(part));
      } else if (part.type === "document") {
        blocks.push({
          type: "document",
          source: {
            type: "base64",
            media_type: part.source.media_type ?? "application/pdf",
            data: part.source.data,
          },
        });
      }
    }

    return blocks;
  }

  private static serializeImage(part: ContentPartImage): any {
    const url = part.image_url.url;
    if (url.startsWith("data:image/")) {
      const [header, data] = url.split(",", 2);
      const mediaType = header.split(";")[0].replace("data:", "") || "image/jpeg";
      return {
        type: "image",
        source: { type: "base64", media_type: mediaType, data },
      };
    }
    return {
      type: "image",
      source: { type: "url", url },
    };
  }

  private static serializeToolMessage(
    message: ToolMessage,
    use_cache: boolean
  ): any {
    const cacheControl = use_cache ? { type: "ephemeral" } : undefined;
    const content = message.destroyed
      ? "<removed to save context>"
      : this.serializeToolResultContent(message.content);

    return {
      type: "tool_result",
      tool_use_id: message.tool_call_id,
      content,
      is_error: message.is_error ?? false,
      ...(cacheControl ? { cache_control: cacheControl } : {}),
    };
  }

  private static serializeToolResultContent(
    content: string | (ContentPartText | ContentPartImage)[]
  ): any {
    if (typeof content === "string") return content;

    const blocks: any[] = [];
    for (const part of content) {
      if (part.type === "text") {
        blocks.push({ type: "text", text: part.text });
      } else if (part.type === "image_url") {
        blocks.push(this.serializeImage(part));
      }
    }

    return blocks.length ? blocks : "";
  }

  private static serializeToolCalls(tool_calls: ToolCall[], use_cache: boolean): any[] {
    const cacheControl = use_cache ? { type: "ephemeral" } : undefined;
    return tool_calls.map((tc, i) => {
      let input: any = {};
      try {
        input = JSON.parse(tc.function.arguments || "{}");
      } catch {
        input = { arguments: tc.function.arguments };
      }
      return {
        type: "tool_use",
        id: tc.id,
        name: tc.function.name,
        input,
        ...(use_cache && i === tool_calls.length - 1 ? { cache_control: cacheControl } : {}),
      };
    });
  }

  private static serializeAssistantContent(message: AssistantMessage): any {
    const blocks: any[] = [];

    if (message.content !== null && message.content !== undefined) {
      if (typeof message.content === "string") {
        blocks.push({
          type: "text",
          text: message.content,
          ...(message.cache && !message.tool_calls?.length
            ? { cache_control: { type: "ephemeral" } }
            : {}),
        });
      } else {
        const parts = message.content;
        for (let i = 0; i < parts.length; i += 1) {
          const part = parts[i];
          const isLastContent = i === parts.length - 1 && !message.tool_calls?.length;
          if (part.type === "text") {
            blocks.push({
              type: "text",
              text: part.text,
              ...(message.cache && isLastContent
                ? { cache_control: { type: "ephemeral" } }
                : {}),
            });
          } else if (part.type === "thinking") {
            blocks.push({
              type: "thinking",
              thinking: part.thinking,
              signature: part.signature ?? "",
            });
          } else if (part.type === "redacted_thinking") {
            blocks.push({ type: "redacted_thinking", data: part.data });
          } else if (part.type === "refusal") {
            blocks.push({ type: "text", text: `[Refusal] ${part.refusal}` });
          }
        }
      }
    }

    if (message.tool_calls && message.tool_calls.length) {
      const toolBlocks = this.serializeToolCalls(message.tool_calls, !!message.cache);
      blocks.push(...toolBlocks);
    }

    if (!blocks.length) {
      blocks.push({
        type: "text",
        text: "",
        ...(message.cache ? { cache_control: { type: "ephemeral" } } : {}),
      });
    }

    if (message.cache || blocks.length > 1) return blocks;
    const only = blocks[0];
    if (only.type === "text" && !only.cache_control) return only.text;
    return blocks;
  }

  private static cleanCacheMessages(messages: NonSystemMessage[]): void {
    if (!messages.length) return;
    let lastCacheIndex = -1;
    for (let i = messages.length - 1; i >= 0; i -= 1) {
      if (messages[i].cache) {
        lastCacheIndex = i;
        break;
      }
    }
    if (lastCacheIndex >= 0) {
      for (let i = 0; i < messages.length; i += 1) {
        if (i !== lastCacheIndex && messages[i].cache) {
          messages[i].cache = false;
        }
      }
    }
  }
}
