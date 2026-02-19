import type { BaseChatModel, ToolChoice, GateDefinition } from "../crystal/crystal";
import type { AnyMessage, AssistantMessage, ToolMessage } from "../crystal/messages";
import { extractToolMessageText } from "../crystal/messages";
import type { Circle } from "../circle/circle";
import type { DependencyOverrides } from "../circle/gate/depends";
import type { GateResult } from "../circle/gate/gate";
import { TaskComplete } from "./errors";
import { executeToolCall, extractScreenshot, runAgentLoop } from "./runtime";
import {
  StepStartEvent,
  StepCompleteEvent,
  ToolCallEvent,
  ToolResultEvent,
  FinalResponseEvent,
} from "./events";

export type CoreAgentOptions = {
  llm: BaseChatModel;
  tools: GateResult[];
  system_prompt?: string | null;
  max_iterations?: number;
  tool_choice?: ToolChoice;
  require_done_tool?: boolean;
  dependency_overrides?: DependencyOverrides | null;
};

export class CoreAgent {
  llm: BaseChatModel;
  tools: GateResult[];
  system_prompt: string | null;
  max_iterations: number;
  tool_choice: ToolChoice;
  require_done_tool: boolean;
  dependency_overrides: DependencyOverrides | null;

  private messages: AnyMessage[] = [];
  private tool_map: Map<string, GateResult> = new Map();
  private circle: Circle;

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

    // Build a Circle for tool dispatch. Constructed directly (not via Circle()
    // constructor) because CoreAgent supports running without a done gate.
    const tool_map = this.tool_map;
    const tool_definitions: GateDefinition[] = this.tools.map((t) => t.definition);
    this.circle = {
      gates: this.tools,
      wards: [{ max_turns: this.max_iterations, require_done_tool: this.require_done_tool }],
      crystalView(toolChoice?: ToolChoice) {
        return { tool_definitions, tool_choice: toolChoice ?? "auto" };
      },
      async execute(utterance: AssistantMessage, execOptions) {
        const { dependency_overrides, on_event, on_tool_result } = execOptions;
        const emit = on_event ?? (() => {});
        const messages: ToolMessage[] = [];
        const gate_calls: { gate_name: string; arguments: string; result: string; is_error: boolean }[] = [];

        let stepNumber = 0;
        for (const toolCall of utterance.tool_calls ?? []) {
          stepNumber += 1;
          let args: Record<string, any> = {};
          try {
            args = JSON.parse(toolCall.function.arguments ?? "{}");
          } catch {
            args = { _raw: toolCall.function.arguments };
          }

          emit(new StepStartEvent(toolCall.id, toolCall.function.name, stepNumber));
          emit(new ToolCallEvent(toolCall.function.name, args, toolCall.id, toolCall.function.name));

          const stepStart = Date.now();
          try {
            const toolResult = await executeToolCall({
              tool_call: toolCall,
              tool_map,
              dependency_overrides,
            });
            messages.push(toolResult);
            if (on_tool_result) on_tool_result(toolResult);

            const resultText = typeof toolResult.content === "string"
              ? toolResult.content
              : JSON.stringify(toolResult.content);

            emit(new ToolResultEvent(
              toolCall.function.name,
              extractToolMessageText(toolResult),
              toolCall.id,
              toolResult.is_error ?? false,
              extractScreenshot(toolResult),
            ));
            emit(new StepCompleteEvent(
              toolCall.id,
              toolResult.is_error ? "error" : "completed",
              Date.now() - stepStart,
            ));

            gate_calls.push({
              gate_name: toolCall.function.name,
              arguments: toolCall.function.arguments ?? "{}",
              result: resultText,
              is_error: toolResult.is_error ?? false,
            });
          } catch (err) {
            if (err instanceof TaskComplete) {
              const completionMsg: ToolMessage = {
                role: "tool",
                tool_call_id: toolCall.id,
                tool_name: toolCall.function.name,
                content: `Task completed: ${err.message}`,
                is_error: false,
              } as ToolMessage;
              messages.push(completionMsg);

              emit(new ToolResultEvent(
                toolCall.function.name,
                `Task completed: ${err.message}`,
                toolCall.id,
                false,
              ));
              emit(new FinalResponseEvent(err.message));

              gate_calls.push({
                gate_name: toolCall.function.name,
                arguments: toolCall.function.arguments ?? "{}",
                result: `Task completed: ${err.message}`,
                is_error: false,
              });

              return { messages, gate_calls, done: err.message };
            }
            throw err;
          }
        }

        return { messages, gate_calls };
      },
    };
  }

  get tool_definitions(): GateDefinition[] {
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
    const effectiveToolChoice = this.require_done_tool
      ? "required"
      : this.tool_choice;
    return runAgentLoop({
      llm: this.llm,
      tools: this.tools,
      circle: this.circle,
      messages: this.messages,
      system_prompt: this.system_prompt,
      max_iterations: this.max_iterations,
      require_done_tool: this.require_done_tool,
      dependency_overrides: this.dependency_overrides,
      invoke_llm: async () =>
        this.llm.ainvoke(
          this.messages,
          this.tools.length ? this.tool_definitions : null,
          this.tools.length ? effectiveToolChoice : null,
        ),
    });
  }
}
