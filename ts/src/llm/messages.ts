/*
  Message and content-part types.
  Modeled after bu_agent_sdk.llm.messages.
*/

export type SupportedImageMediaType =
  | "image/jpeg"
  | "image/png"
  | "image/gif"
  | "image/webp";

export type SupportedDocumentMediaType = "application/pdf";

export type ContentPartText = { type: "text"; text: string };
export type ContentPartRefusal = { type: "refusal"; refusal: string };
export type ContentPartThinking = {
  type: "thinking";
  thinking: string;
  signature?: string | null;
};
export type ContentPartRedactedThinking = {
  type: "redacted_thinking";
  data: string;
};

export type ImageURL = {
  url: string;
  detail?: "auto" | "low" | "high";
  media_type?: SupportedImageMediaType;
};

export type ContentPartImage = { type: "image_url"; image_url: ImageURL };

export type DocumentSource = {
  data: string;
  media_type?: SupportedDocumentMediaType;
};

export type ContentPartDocument = {
  type: "document";
  source: DocumentSource;
};

export type ContentPart =
  | ContentPartText
  | ContentPartRefusal
  | ContentPartThinking
  | ContentPartRedactedThinking
  | ContentPartImage
  | ContentPartDocument;

export type FunctionCall = {
  name: string;
  arguments: string;
};

export type ToolCall = {
  id: string;
  function: FunctionCall;
  type: "function";
  thought_signature?: string | null;
};

export type BaseMessage = {
  role: "user" | "system" | "assistant" | "tool" | "developer";
  cache?: boolean;
};

export type UserMessage = BaseMessage & {
  role: "user";
  content: string | ContentPart[];
  name?: string;
};

export type SystemMessage = BaseMessage & {
  role: "system";
  content: string | ContentPartText[];
  name?: string;
};

export type DeveloperMessage = BaseMessage & {
  role: "developer";
  content: string | ContentPartText[];
  name?: string;
};

export type AssistantMessage = BaseMessage & {
  role: "assistant";
  content:
    | string
    | (ContentPartText | ContentPartRefusal | ContentPartThinking | ContentPartRedactedThinking)[]
    | null;
  name?: string;
  refusal?: string | null;
  tool_calls?: ToolCall[] | null;
};

export type ToolMessage = BaseMessage & {
  role: "tool";
  tool_call_id: string;
  tool_name: string;
  content: string | (ContentPartText | ContentPartImage)[];
  is_error?: boolean;
  ephemeral?: boolean;
  destroyed?: boolean;
};

export type AnyMessage =
  | UserMessage
  | SystemMessage
  | DeveloperMessage
  | AssistantMessage
  | ToolMessage;

export function extractTextFromContent(
  content: string | ContentPart[] | null | undefined
): string {
  if (!content) return "";
  if (typeof content === "string") return content;
  const parts = content as ContentPart[];
  return parts
    .map((part) => {
      if (part.type === "text") return part.text;
      if (part.type === "refusal") return `[Refusal] ${part.refusal}`;
      return "";
    })
    .filter(Boolean)
    .join("\n");
}

export function extractThinkingFromContent(
  content: string | ContentPart[] | null | undefined
): string | null {
  if (!content || typeof content === "string") return null;
  const thoughts: string[] = [];
  for (const part of content) {
    if (part.type === "thinking") thoughts.push(part.thinking);
  }
  return thoughts.length ? thoughts.join("\n") : null;
}

export function extractToolMessageText(message: ToolMessage): string {
  const content = message.content;
  if (typeof content === "string") return content;
  return content
    .map((part) => (part.type === "text" ? part.text : ""))
    .filter(Boolean)
    .join("\n");
}
