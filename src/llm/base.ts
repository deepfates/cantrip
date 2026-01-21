import type { AnyMessage } from "./messages";
import type { ChatInvokeCompletion } from "./views";

export type JsonSchema = Record<string, unknown>;

export type ToolDefinition = {
  name: string;
  description: string;
  parameters: JsonSchema;
  strict?: boolean;
};

export type ToolChoice = "auto" | "required" | "none" | string;

export interface BaseChatModel {
  model: string;
  provider: string;
  name: string;
  ainvoke(
    messages: AnyMessage[],
    tools?: ToolDefinition[] | null,
    tool_choice?: ToolChoice | null,
    extra?: Record<string, unknown>
  ): Promise<ChatInvokeCompletion>;
}
