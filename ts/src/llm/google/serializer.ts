import type {
  AnyMessage,
  AssistantMessage,
  ContentPart,
  DeveloperMessage,
  SystemMessage,
  ToolMessage,
  UserMessage,
} from "../messages";
import { extractToolMessageText } from "../messages";

export type GoogleContent = {
  role: "user" | "model";
  parts: any[];
};

export class GoogleMessageSerializer {
  static serializeMessages(
    messages: AnyMessage[],
    include_system_in_user = false
  ): { contents: GoogleContent[]; system_instruction?: string } {
    const copy = JSON.parse(JSON.stringify(messages)) as AnyMessage[];
    const contents: GoogleContent[] = [];
    let system_instruction: string | undefined;
    const systemParts: string[] = [];

    let pendingToolParts: any[] = [];
    const flushToolParts = () => {
      if (pendingToolParts.length) {
        contents.push({ role: "user", parts: pendingToolParts });
        pendingToolParts = [];
      }
    };

    for (const message of copy) {
      if (message.role === "system" || message.role === "developer") {
        flushToolParts();
        const content = message.content;
        let text = "";
        if (typeof content === "string") text = content;
        else if (Array.isArray(content)) {
          text = content
            .filter((p) => p.type === "text")
            .map((p) => p.text)
            .join("\n");
        }
        if (include_system_in_user) {
          if (text) systemParts.push(text);
        } else {
          system_instruction = text || system_instruction;
        }
        continue;
      }

      if (message.role === "tool") {
        const tool = message as ToolMessage;
        const responseData = tool.destroyed
          ? { result: "<removed to save context>" }
          : tool.is_error
          ? { error: extractToolMessageText(tool) }
          : safeJsonOrResult(extractToolMessageText(tool));

        pendingToolParts.push({
          functionResponse: {
            name: tool.tool_name,
            response: responseData,
          },
        });
        continue;
      }

      flushToolParts();

      if (message.role === "user") {
        const user = message as UserMessage;
        const parts = serializeContent(user.content);
        if (
          include_system_in_user &&
          systemParts.length &&
          contents.length === 0
        ) {
          const systemText = systemParts.join("\n\n");
          if (parts.length) {
            if (parts[0].text) {
              parts[0].text = `${systemText}\n\n${parts[0].text}`;
            } else {
              parts.unshift({ text: systemText });
            }
          } else {
            parts.push({ text: systemText });
          }
        }
        contents.push({ role: "user", parts });
        continue;
      }

      if (message.role === "assistant") {
        const assistant = message as AssistantMessage;
        const parts = serializeContent(assistant.content ?? "");
        if (assistant.tool_calls?.length) {
          for (const tc of assistant.tool_calls) {
            const args = safeParseJson(tc.function.arguments);
            parts.push({
              functionCall: {
                name: tc.function.name,
                args,
                id: tc.id,
              },
              ...(tc.thought_signature
                ? { thoughtSignature: tc.thought_signature }
                : {}),
            });
          }
        }
        contents.push({ role: "model", parts });
        continue;
      }
    }

    flushToolParts();

    return { contents, system_instruction };
  }
}

function safeParseJson(raw: string): Record<string, unknown> {
  try {
    return JSON.parse(raw || "{}") as Record<string, unknown>;
  } catch {
    return { raw_arguments: raw };
  }
}

function safeJsonOrResult(text: string): Record<string, unknown> {
  try {
    return JSON.parse(text);
  } catch {
    return { result: text };
  }
}

function serializeContent(
  content: string | ContentPart[] | null
): Array<Record<string, any>> {
  if (!content) return [];
  if (typeof content === "string") return [{ text: content }];

  const parts: Array<Record<string, any>> = [];
  for (const part of content) {
    if (part.type === "text") {
      if (part.text) parts.push({ text: part.text });
    } else if (part.type === "refusal") {
      parts.push({ text: `[Refusal] ${part.refusal}` });
    } else if (part.type === "image_url") {
      const { mimeType, data } = parseDataUrl(part.image_url.url);
      if (data && mimeType) {
        parts.push({ inlineData: { mimeType, data } });
      } else {
        parts.push({ text: `[Image] ${part.image_url.url}` });
      }
    } else if (part.type === "document") {
      const data = part.source.data;
      const mimeType = part.source.media_type ?? "application/pdf";
      parts.push({ inlineData: { mimeType, data } });
    }
  }

  return parts;
}

function parseDataUrl(url: string): { mimeType: string | null; data: string | null } {
  if (!url.startsWith("data:")) return { mimeType: null, data: null };
  const [header, data] = url.split(",", 2);
  if (!header || !data) return { mimeType: null, data: null };
  const mimeType = header.split(";")[0].replace("data:", "");
  return { mimeType: mimeType || null, data };
}
