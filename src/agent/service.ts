import { promises as fs } from "fs";
import path from "path";
import type { BaseChatModel, ToolChoice, ToolDefinition } from "../llm/base";
import type {
  AnyMessage,
  AssistantMessage,
  ToolCall,
  ToolMessage,
  ContentPartImage,
} from "../llm/messages";
import { extractToolMessageText } from "../llm/messages";
import type { ChatInvokeCompletion } from "../llm/views";
import { hasToolCalls } from "../llm/views";
import { Tool } from "../tools/decorator";
import type { DependencyOverrides } from "../tools/depends";
import { CompactionService } from "./compaction/service";
import type { CompactionConfig } from "./compaction/models";
import { TokenCost } from "../tokens/service";
import {
  type AgentEvent,
  FinalResponseEvent,
  HiddenUserMessageEvent,
  StepCompleteEvent,
  StepStartEvent,
  TextEvent,
  ThinkingEvent,
  ToolCallEvent,
  ToolResultEvent,
} from "./events";

export class TaskComplete extends Error {
  message: string;
  constructor(message: string) {
    super(message);
    this.name = "TaskComplete";
    this.message = message;
  }
}

export type AgentOptions = {
  llm: BaseChatModel;
  tools: Tool<any>[];
  system_prompt?: string | null;
  max_iterations?: number;
  tool_choice?: ToolChoice;
  compaction?: CompactionConfig | null;
  include_cost?: boolean;
  dependency_overrides?: DependencyOverrides | null;
  ephemeral_storage_path?: string | null;
  require_done_tool?: boolean;
  llm_max_retries?: number;
  llm_retry_base_delay?: number;
  llm_retry_max_delay?: number;
  llm_retryable_status_codes?: Set<number> | number[];
};

export class Agent {
  llm: BaseChatModel;
  tools: Tool<any>[];
  system_prompt: string | null;
  max_iterations: number;
  tool_choice: ToolChoice;
  compaction: CompactionConfig | null;
  include_cost: boolean;
  dependency_overrides: DependencyOverrides | null;
  ephemeral_storage_path: string | null;
  require_done_tool: boolean;
  llm_max_retries: number;
  llm_retry_base_delay: number;
  llm_retry_max_delay: number;
  llm_retryable_status_codes: Set<number>;

  private messages: AnyMessage[] = [];
  private tool_map: Map<string, Tool<any>> = new Map();
  private compaction_service: CompactionService;
  private token_cost: TokenCost;

  constructor(options: AgentOptions) {
    this.llm = options.llm;
    this.tools = options.tools;
    this.system_prompt = options.system_prompt ?? null;
    this.max_iterations = options.max_iterations ?? 200;
    this.tool_choice = options.tool_choice ?? "auto";
    this.compaction = options.compaction ?? null;
    this.include_cost = options.include_cost ?? false;
    this.dependency_overrides = options.dependency_overrides ?? null;
    this.ephemeral_storage_path = options.ephemeral_storage_path ?? null;
    this.require_done_tool = options.require_done_tool ?? false;
    this.llm_max_retries = options.llm_max_retries ?? 5;
    this.llm_retry_base_delay = options.llm_retry_base_delay ?? 1.0;
    this.llm_retry_max_delay = options.llm_retry_max_delay ?? 60.0;
    this.llm_retryable_status_codes = new Set(
      options.llm_retryable_status_codes ?? [429, 500, 502, 503, 504],
    );

    for (const tool of this.tools) {
      this.tool_map.set(tool.name, tool);
    }

    this.token_cost = new TokenCost(this.include_cost);
    this.compaction_service = new CompactionService({
      config: this.compaction ?? undefined,
      llm: this.llm,
      token_cost: this.token_cost,
    });
  }

  get tool_definitions(): ToolDefinition[] {
    return this.tools.map((t) => t.definition);
  }

  get history(): AnyMessage[] {
    return [...this.messages];
  }

  async get_usage() {
    return this.token_cost.getUsageSummary();
  }

  clear_history() {
    this.messages = [];
    this.token_cost.clearHistory();
  }

  load_history(messages: AnyMessage[]) {
    this.messages = [...messages];
    this.token_cost.clearHistory();
  }

  private async destroyEphemeralMessages(): Promise<void> {
    const ephemeralByTool = new Map<string, ToolMessage[]>();

    for (const msg of this.messages) {
      if (msg.role !== "tool") continue;
      const toolMsg = msg as ToolMessage;
      if (!toolMsg.ephemeral) continue;
      if (toolMsg.destroyed) continue;
      const list = ephemeralByTool.get(toolMsg.tool_name) ?? [];
      list.push(toolMsg);
      ephemeralByTool.set(toolMsg.tool_name, list);
    }

    for (const [toolName, toolMessages] of ephemeralByTool.entries()) {
      const tool = this.tool_map.get(toolName);
      const keepCount = tool
        ? typeof tool.ephemeral === "number"
          ? tool.ephemeral
          : 1
        : 1;
      const toDestroy =
        keepCount > 0 ? toolMessages.slice(0, -keepCount) : toolMessages;

      for (const msg of toDestroy) {
        if (this.ephemeral_storage_path) {
          await fs.mkdir(this.ephemeral_storage_path, { recursive: true });
          const filename = `${msg.tool_call_id}.json`;
          const filepath = path.join(this.ephemeral_storage_path, filename);
          const contentData =
            typeof msg.content === "string" ? msg.content : msg.content;
          const saved = {
            tool_call_id: msg.tool_call_id,
            tool_name: msg.tool_name,
            content: contentData,
            is_error: msg.is_error ?? false,
          };
          await fs.writeFile(filepath, JSON.stringify(saved, null, 2));
        }
        msg.destroyed = true;
      }
    }
  }

  private async executeToolCall(tool_call: ToolCall): Promise<ToolMessage> {
    const tool = this.tool_map.get(tool_call.function.name);
    if (!tool) {
      return {
        role: "tool",
        tool_call_id: tool_call.id,
        tool_name: tool_call.function.name,
        content: `Error: Unknown tool '${tool_call.function.name}'`,
        is_error: true,
        ephemeral: false,
        destroyed: false,
      } as ToolMessage;
    }

    try {
      let args: Record<string, any> = {};
      try {
        args = JSON.parse(tool_call.function.arguments ?? "{}");
      } catch {
        args = {};
      }

      const result = await tool.execute(
        args,
        this.dependency_overrides ?? undefined,
      );
      const is_ephemeral = Boolean(tool.ephemeral);

      return {
        role: "tool",
        tool_call_id: tool_call.id,
        tool_name: tool.name,
        content: result,
        is_error: false,
        ephemeral: is_ephemeral,
        destroyed: false,
      } as ToolMessage;
    } catch (err) {
      if (err instanceof TaskComplete) throw err;
      return {
        role: "tool",
        tool_call_id: tool_call.id,
        tool_name: tool.name,
        content: `Error executing tool: ${String((err as any)?.message ?? err)}`,
        is_error: true,
        ephemeral: false,
        destroyed: false,
      } as ToolMessage;
    }
  }

  private extractScreenshot(toolMessage: ToolMessage): string | null {
    const content = toolMessage.content;
    if (typeof content === "string") return null;
    if (Array.isArray(content)) {
      for (const part of content) {
        if ((part as ContentPartImage).type === "image_url") {
          const url = (part as ContentPartImage).image_url.url;
          if (url.startsWith("data:image/png;base64,"))
            return url.split(",", 2)[1];
          if (url.startsWith("data:image/jpeg;base64,"))
            return url.split(",", 2)[1];
        }
      }
    }
    return null;
  }

  private async invokeLLM(): Promise<ChatInvokeCompletion> {
    let lastError: any = null;

    for (let attempt = 0; attempt < this.llm_max_retries; attempt += 1) {
      try {
        const response = await this.llm.ainvoke(
          this.messages,
          this.tools.length ? this.tool_definitions : null,
          this.tools.length ? this.tool_choice : null,
        );

        if (response.usage) {
          this.token_cost.addUsage(this.llm.model, response.usage);
        }

        return response;
      } catch (err: any) {
        lastError = err;
        const status = err?.status_code ?? err?.status ?? null;
        const retryable = status && this.llm_retryable_status_codes.has(status);

        const isTimeout =
          typeof err?.message === "string" &&
          (err.message.toLowerCase().includes("timeout") ||
            err.message.toLowerCase().includes("cancelled"));
        const isConnection =
          typeof err?.message === "string" &&
          (err.message.toLowerCase().includes("connection") ||
            err.message.toLowerCase().includes("connect"));

        if (
          (retryable || isTimeout || isConnection) &&
          attempt < this.llm_max_retries - 1
        ) {
          const delay = Math.min(
            this.llm_retry_base_delay * 2 ** attempt,
            this.llm_retry_max_delay,
          );
          const jitter = Math.random() * delay * 0.1;
          const totalDelay = delay + jitter;
          await new Promise((r) => setTimeout(r, totalDelay * 1000));
          continue;
        }
        throw err;
      }
    }

    if (lastError) throw lastError;
    throw new Error("Retry loop completed without return or exception");
  }

  private async generateMaxIterationsSummary(): Promise<string> {
    const summaryPrompt = `The task has reached the maximum number of steps allowed.
Please provide a concise summary of:
1. What was accomplished so far
2. What actions were taken
3. What remains incomplete (if anything)
4. Any partial results or findings

Keep the summary brief but informative.`;

    this.messages.push({ role: "user", content: summaryPrompt } as AnyMessage);
    try {
      const response = await this.llm.ainvoke(this.messages, null, null);
      return `[Max iterations reached]\n\n${response.content ?? "Unable to generate summary."}`;
    } catch (err) {
      return `Task stopped after ${this.max_iterations} iterations. Unable to generate summary due to error.`;
    } finally {
      this.messages.pop();
    }
  }

  protected async get_incomplete_todos_prompt(): Promise<string | null> {
    return null;
  }

  private async checkAndCompact(
    response: ChatInvokeCompletion,
  ): Promise<boolean> {
    this.compaction_service.updateUsage(response.usage ?? null);
    const { messages, result } = await this.compaction_service.checkAndCompact(
      this.messages,
      this.llm,
    );
    if (result.compacted) {
      this.messages = [...messages];
      return true;
    }
    return false;
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
    let incomplete_todos_prompted = false;

    while (iterations < this.max_iterations) {
      iterations += 1;
      await this.destroyEphemeralMessages();

      const response = await this.invokeLLM();

      const assistantMessage: AssistantMessage = {
        role: "assistant",
        content: response.content ?? null,
        tool_calls: response.tool_calls ?? null,
      };
      this.messages.push(assistantMessage);

      if (!hasToolCalls(response)) {
        if (!this.require_done_tool) {
          if (!incomplete_todos_prompted) {
            const prompt = await this.get_incomplete_todos_prompt();
            if (prompt) {
              incomplete_todos_prompted = true;
              this.messages.push({
                role: "user",
                content: prompt,
              } as AnyMessage);
              continue;
            }
          }
          await this.checkAndCompact(response);
          return response.content ?? "";
        }
        continue;
      }

      for (const toolCall of response.tool_calls ?? []) {
        try {
          const toolResult = await this.executeToolCall(toolCall);
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

      await this.checkAndCompact(response);
    }

    return await this.generateMaxIterationsSummary();
  }

  async *query_stream(message: string): AsyncGenerator<AgentEvent> {
    if (!this.messages.length && this.system_prompt) {
      this.messages.push({
        role: "system",
        content: this.system_prompt,
        cache: true,
      } as AnyMessage);
    }

    this.messages.push({ role: "user", content: message } as AnyMessage);

    let iterations = 0;
    let incomplete_todos_prompted = false;

    while (iterations < this.max_iterations) {
      iterations += 1;
      await this.destroyEphemeralMessages();

      const response = await this.invokeLLM();

      if (response.thinking) {
        yield new ThinkingEvent(response.thinking);
      }

      const assistantMessage: AssistantMessage = {
        role: "assistant",
        content: response.content ?? null,
        tool_calls: response.tool_calls ?? null,
      };
      this.messages.push(assistantMessage);

      if (!hasToolCalls(response)) {
        if (!this.require_done_tool) {
          if (!incomplete_todos_prompted) {
            const prompt = await this.get_incomplete_todos_prompt();
            if (prompt) {
              incomplete_todos_prompted = true;
              this.messages.push({
                role: "user",
                content: prompt,
              } as AnyMessage);
              yield new HiddenUserMessageEvent(prompt);
              continue;
            }
          }
          await this.checkAndCompact(response);
          if (response.content) yield new TextEvent(response.content);
          yield new FinalResponseEvent(response.content ?? "");
          return;
        }
        if (response.content) yield new TextEvent(response.content);
        continue;
      }

      if (response.content) {
        yield new TextEvent(response.content);
      }

      let stepNumber = 0;
      for (const toolCall of response.tool_calls ?? []) {
        stepNumber += 1;
        let args: Record<string, any> = {};
        try {
          args = JSON.parse(toolCall.function.arguments ?? "{}");
        } catch {
          args = { _raw: toolCall.function.arguments };
        }

        yield new StepStartEvent(
          toolCall.id,
          toolCall.function.name,
          stepNumber,
        );
        yield new ToolCallEvent(
          toolCall.function.name,
          args,
          toolCall.id,
          toolCall.function.name,
        );

        const start = Date.now();
        try {
          const toolResult = await this.executeToolCall(toolCall);
          this.messages.push(toolResult);
          const screenshot = this.extractScreenshot(toolResult);
          yield new ToolResultEvent(
            toolCall.function.name,
            extractToolMessageText(toolResult),
            toolCall.id,
            toolResult.is_error ?? false,
            screenshot,
          );
          const duration = Date.now() - start;
          yield new StepCompleteEvent(
            toolCall.id,
            toolResult.is_error ? "error" : "completed",
            duration,
          );
        } catch (err) {
          if (err instanceof TaskComplete) {
            this.messages.push({
              role: "tool",
              tool_call_id: toolCall.id,
              tool_name: toolCall.function.name,
              content: `Task completed: ${err.message}`,
              is_error: false,
            } as ToolMessage);
            yield new ToolResultEvent(
              toolCall.function.name,
              `Task completed: ${err.message}`,
              toolCall.id,
              false,
            );
            yield new FinalResponseEvent(err.message);
            return;
          }
          throw err;
        }
      }

      await this.checkAndCompact(response);
    }

    const summary = await this.generateMaxIterationsSummary();
    yield new FinalResponseEvent(summary);
  }
}
