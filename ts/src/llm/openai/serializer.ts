import type {
  AnyMessage,
  AssistantMessage,
  ContentPartDocument,
  ContentPartImage,
  ContentPartRefusal,
  ContentPartText,
  DeveloperMessage,
  SystemMessage,
  ToolCall,
  ToolMessage,
  UserMessage,
} from "../messages";

export type OpenAIMessageParam = Record<string, unknown>;

export class OpenAIMessageSerializer {
  static serializeMessages(messages: AnyMessage[]): OpenAIMessageParam[] {
    return messages.map((m) => OpenAIMessageSerializer.serialize(m));
  }

  static serialize(message: AnyMessage): OpenAIMessageParam {
    switch (message.role) {
      case "user":
        return OpenAIMessageSerializer.serializeUser(message as UserMessage);
      case "system":
        return OpenAIMessageSerializer.serializeSystem(message as SystemMessage);
      case "developer":
        return OpenAIMessageSerializer.serializeDeveloper(
          message as DeveloperMessage
        );
      case "assistant":
        return OpenAIMessageSerializer.serializeAssistant(
          message as AssistantMessage
        );
      case "tool":
        return OpenAIMessageSerializer.serializeTool(message as ToolMessage);
      default:
        throw new Error(`Unknown message role: ${(message as AnyMessage).role}`);
    }
  }

  private static serializeUser(message: UserMessage): OpenAIMessageParam {
    return {
      role: "user",
      content: OpenAIMessageSerializer.serializeUserContent(message.content),
      ...(message.name ? { name: message.name } : {}),
    };
  }

  private static serializeSystem(message: SystemMessage): OpenAIMessageParam {
    return {
      role: "system",
      content: OpenAIMessageSerializer.serializeSystemContent(message.content),
      ...(message.name ? { name: message.name } : {}),
    };
  }

  private static serializeDeveloper(
    message: DeveloperMessage
  ): OpenAIMessageParam {
    return {
      role: "developer",
      content: OpenAIMessageSerializer.serializeSystemContent(message.content),
      ...(message.name ? { name: message.name } : {}),
    };
  }

  private static serializeAssistant(
    message: AssistantMessage
  ): OpenAIMessageParam {
    const result: OpenAIMessageParam = { role: "assistant" };

    if (message.content !== null && message.content !== undefined) {
      result.content = OpenAIMessageSerializer.serializeAssistantContent(
        message.content
      );
    }

    if (message.name) result.name = message.name;
    if (message.refusal) result.refusal = message.refusal;

    if (message.tool_calls && message.tool_calls.length) {
      result.tool_calls = message.tool_calls.map((tc) =>
        OpenAIMessageSerializer.serializeToolCall(tc)
      );
    }

    return result;
  }

  private static serializeTool(message: ToolMessage): OpenAIMessageParam {
    let content: string | Array<{ type: "text"; text: string }> = "";

    if (message.destroyed) {
      content = "<removed to save context>";
    } else {
      content = OpenAIMessageSerializer.serializeToolMessageContent(message);
    }

    if (Array.isArray(content)) {
      content = content.map((part) => part.text).join("\n");
    }

    return {
      role: "tool",
      tool_call_id: message.tool_call_id,
      content,
    };
  }

  private static serializeToolCall(tool_call: ToolCall): OpenAIMessageParam {
    return {
      id: tool_call.id,
      type: "function",
      function: {
        name: tool_call.function.name,
        arguments: tool_call.function.arguments,
      },
    };
  }

  private static serializeUserContent(
    content: string | (ContentPartText | ContentPartImage | ContentPartDocument)[]
  ):
    | string
    | Array<{ type: "text"; text: string } | { type: "image_url"; image_url: any }> {
    if (typeof content === "string") return content;

    const parts: Array<
      { type: "text"; text: string } | { type: "image_url"; image_url: any }
    > = [];

    for (const part of content) {
      if (part.type === "text") {
        parts.push({ type: "text", text: part.text });
      } else if (part.type === "image_url") {
        parts.push({
          type: "image_url",
          image_url: {
            url: part.image_url.url,
            detail: part.image_url.detail ?? "auto",
          },
        });
      } else if (part.type === "document") {
        parts.push({ type: "text", text: "[PDF document attached]" });
      }
    }

    return parts;
  }

  private static serializeSystemContent(
    content: string | ContentPartText[]
  ):
    | string
    | Array<{
        type: "text";
        text: string;
      }> {
    if (typeof content === "string") return content;

    return content
      .filter((p) => p.type === "text")
      .map((p) => ({ type: "text", text: p.text }));
  }

  private static serializeAssistantContent(
    content: string | (ContentPartText | ContentPartRefusal)[]
  ):
    | string
    | Array<{ type: "text"; text: string } | { type: "refusal"; refusal: string }> {
    if (typeof content === "string") return content;

    const parts: Array<
      { type: "text"; text: string } | { type: "refusal"; refusal: string }
    > = [];

    for (const part of content) {
      if (part.type === "text") {
        parts.push({ type: "text", text: part.text });
      } else if (part.type === "refusal") {
        parts.push({ type: "refusal", refusal: part.refusal });
      }
    }

    return parts;
  }

  private static serializeToolMessageContent(
    message: ToolMessage
  ): string | Array<{ type: "text"; text: string }> {
    const content = message.content;
    if (typeof content === "string") return content;

    const parts: Array<{ type: "text"; text: string }> = [];
    for (const part of content) {
      if (part.type === "text") {
        parts.push({ type: "text", text: part.text });
      } else if (part.type === "image_url") {
        parts.push({ type: "text", text: "[Image attached]" });
      }
    }
    return parts.length ? parts : "";
  }
}
