import type { BaseChatModel, ToolChoice, ToolDefinition } from "../llm/base";
import type {
  AnyMessage,
  AssistantMessage,
  ToolMessage,
} from "../llm/messages";
import { hasToolCalls } from "../llm/views";
import type { DependencyOverrides } from "../tools/depends";
import type { ToolLike } from "../tools/types";
import { TaskComplete } from "./errors";
import { executeToolCall } from "./runtime";

export type CoreAgentOptions = {
  llm: BaseChatModel;
  tools: ToolLike[];
  system_prompt?: string | null;
  max_iterations?: number;
  tool_choice?: ToolChoice;
  require_done_tool?: boolean;
  dependency_overrides?: DependencyOverrides | null;
};

export class CoreAgent {
  llm: BaseChatModel;
  tools: ToolLike[];
  system_prompt: string | null;
  max_iterations: number;
  tool_choice: ToolChoice;
  require_done_tool: boolean;
  dependency_overrides: DependencyOverrides | null;

  private messages: AnyMessage[] = [];
  private tool_map: Map<string, ToolLike> = new Map();

  constructor(options: CoreAgentOptions) {
    this.llm = options.llm;
    this.tools = options.tools;
    this.system_prompt = options.system_prompt ?? null;
    this.max_iterations = options.max_iterations ?? 200;
    this.tool_choice = options.tool_choice ?? "auto";
    this.require_done_tool = options.require_done_tool ?? false;
    this.dependency_overrides = options.dependency_overrides ?? null;

    for (const tool of this.tools) {
      this.tool_map.set(tool.name, tool);
    }
  }

  get tool_definitions(): ToolDefinition[] {
    return this.tools.map((t) => t.definition);
  }

  get history(): AnyMessage[] {
    return [...this.messages];
  }

  clear_history() {
    this.messages = [];
  }

  async query(message: string): Promise<string> {
    if (!this.messages.length && this.system_prompt) {
      this.messages.push({
        role: "system",
        content: this.system_prompt,
        cache: true,
      } as AnyMessage);
    }

    this.messages.push({ role: "user", content: message } as AnyMessage);

    let iterations = 0;

    while (iterations < this.max_iterations) {
      iterations += 1;

      const response = await this.llm.ainvoke(
        this.messages,
        this.tools.length ? this.tool_definitions : null,
        this.tools.length ? this.tool_choice : null,
      );

      const assistantMessage: AssistantMessage = {
        role: "assistant",
        content: response.content ?? null,
        tool_calls: response.tool_calls ?? null,
      };
      this.messages.push(assistantMessage);

      if (!hasToolCalls(response)) {
        if (!this.require_done_tool) {
          return response.content ?? "";
        }
        continue;
      }

      for (const toolCall of response.tool_calls ?? []) {
        try {
          const toolResult = await executeToolCall({
            tool_call: toolCall,
            tool_map: this.tool_map,
            dependency_overrides: this.dependency_overrides,
          });
          this.messages.push(toolResult);
        } catch (err) {
          if (err instanceof TaskComplete) {
            this.messages.push({
              role: "tool",
              tool_call_id: toolCall.id,
              tool_name: toolCall.function.name,
              content: `Task completed: ${err.message}`,
              is_error: false,
            } as ToolMessage);
            return err.message;
          }
          throw err;
        }
      }
    }

    return `Task stopped after ${this.max_iterations} iterations.`;
  }
}
