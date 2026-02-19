import type { AnyMessage } from "./messages";
import type { ChatInvokeCompletion } from "./views";

export type JsonSchema = Record<string, unknown>;

export type GateDefinition = {
  name: string;
  description: string;
  parameters: JsonSchema;
  strict?: boolean;
};

export type ToolChoice = "auto" | "required" | "none" | string | { type: string; name: string };

export interface BaseChatModel {
  model: string;
  provider: string;
  name: string;
  ainvoke(
    messages: AnyMessage[],
    tools?: GateDefinition[] | null,
    tool_choice?: ToolChoice | null,
    extra?: Record<string, unknown>
  ): Promise<ChatInvokeCompletion>;
}
