import type { BaseChatModel, ToolChoice, ToolDefinition } from "../llm/base";
import type { AnyMessage } from "../llm/messages";
import type { DependencyOverrides } from "../tools/depends";
import type { ToolLike } from "../tools/types";
import { runAgentLoop } from "./runtime";

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
    this.messages.push({ role: "user", content: message } as AnyMessage);
    return runAgentLoop({
      llm: this.llm,
      tools: this.tools,
      tool_map: this.tool_map,
      tool_definitions: this.tool_definitions,
      tool_choice: this.tool_choice,
      messages: this.messages,
      system_prompt: this.system_prompt,
      max_iterations: this.max_iterations,
      require_done_tool: this.require_done_tool,
      dependency_overrides: this.dependency_overrides,
      invoke_llm: async () =>
        this.llm.ainvoke(
          this.messages,
          this.tools.length ? this.tool_definitions : null,
          this.tools.length ? this.tool_choice : null,
        ),
    });
  }
}
