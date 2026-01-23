import type { BaseChatModel, ToolChoice, ToolDefinition } from "../llm/base";
import type {
  AnyMessage,
  AssistantMessage,
  ToolMessage,
} from "../llm/messages";
import { extractToolMessageText } from "../llm/messages";
import type { ChatInvokeCompletion } from "../llm/views";
import { hasToolCalls } from "../llm/views";
import type { ToolLike } from "../tools";
import type { DependencyOverrides } from "../tools/depends";
import { CompactionService } from "./compaction/service";
import type { CompactionConfig } from "./compaction/models";
import type { PricingProvider } from "../tokens";
import { UsageTracker } from "../tokens";
import { TaskComplete } from "./errors";
import {
  destroyEphemeralMessages,
  executeToolCall,
  extractScreenshot,
  generateMaxIterationsSummary,
  invokeLLMOnce,
  invokeLLMWithRetries,
} from "./runtime";
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

export { TaskComplete } from "./errors";

export type AgentOptions = {
  llm: BaseChatModel;
  tools: ToolLike[];
  system_prompt?: string | null;
  max_iterations?: number;
  tool_choice?: ToolChoice;
  compaction?: CompactionConfig | null;
  pricing_provider?: PricingProvider | null;
  dependency_overrides?: DependencyOverrides | null;
  ephemeral_storage_path?: string | null;
  require_done_tool?: boolean;
  llm_max_retries?: number;
  llm_retry_base_delay?: number;
  llm_retry_max_delay?: number;
  llm_retryable_status_codes?: Set<number> | number[];
  retry?: { enabled?: boolean };
};

export class Agent {
  llm: BaseChatModel;
  tools: ToolLike[];
  system_prompt: string | null;
  max_iterations: number;
  tool_choice: ToolChoice;
  compaction: CompactionConfig | null;
  pricing_provider: PricingProvider | null;
  dependency_overrides: DependencyOverrides | null;
  ephemeral_storage_path: string | null;
  require_done_tool: boolean;
  llm_max_retries: number;
  llm_retry_base_delay: number;
  llm_retry_max_delay: number;
  llm_retryable_status_codes: Set<number>;
  retry_enabled: boolean;

  private messages: AnyMessage[] = [];
  private tool_map: Map<string, ToolLike> = new Map();
  private compaction_service: CompactionService | null;
  private usage_tracker: UsageTracker;

  constructor(options: AgentOptions) {
    this.llm = options.llm;
    this.tools = options.tools;
    this.system_prompt = options.system_prompt ?? null;
    this.max_iterations = options.max_iterations ?? 200;
    this.tool_choice = options.tool_choice ?? "auto";
    this.compaction = options.compaction ?? null;
    this.pricing_provider = options.pricing_provider ?? null;
    this.dependency_overrides = options.dependency_overrides ?? null;
    this.ephemeral_storage_path = options.ephemeral_storage_path ?? null;
    this.require_done_tool = options.require_done_tool ?? false;
    this.llm_max_retries = options.llm_max_retries ?? 5;
    this.llm_retry_base_delay = options.llm_retry_base_delay ?? 1.0;
    this.llm_retry_max_delay = options.llm_retry_max_delay ?? 60.0;
    this.llm_retryable_status_codes = new Set(
      options.llm_retryable_status_codes ?? [429, 500, 502, 503, 504],
    );
    this.retry_enabled = options.retry?.enabled ?? true;

    for (const tool of this.tools) {
      this.tool_map.set(tool.name, tool);
    }

    this.usage_tracker = new UsageTracker();
    this.compaction_service =
      this.compaction === null
        ? null
        : new CompactionService({
            config: this.compaction ?? undefined,
            llm: this.llm,
            pricing_provider: this.pricing_provider ?? undefined,
          });
  }

  get tool_definitions(): ToolDefinition[] {
    return this.tools.map((t) => t.definition);
  }

  get history(): AnyMessage[] {
    return [...this.messages];
  }

  async get_usage() {
    return this.usage_tracker.getUsageSummary();
  }

  clear_history() {
    this.messages = [];
    this.usage_tracker.clear();
  }

  load_history(messages: AnyMessage[]) {
    this.messages = [...messages];
    this.usage_tracker.clear();
  }

  protected async get_incomplete_todos_prompt(): Promise<string | null> {
    return null;
  }

  private async checkAndCompact(
    response: ChatInvokeCompletion,
  ): Promise<boolean> {
    if (!this.compaction_service) return false;
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
      await destroyEphemeralMessages({
        messages: this.messages,
        tool_map: this.tool_map,
        ephemeral_storage_path: this.ephemeral_storage_path,
      });

      const response = this.retry_enabled
        ? await invokeLLMWithRetries({
            llm: this.llm,
            messages: this.messages,
            tools: this.tools,
            tool_definitions: this.tool_definitions,
            tool_choice: this.tool_choice,
            usage_tracker: this.usage_tracker,
            llm_max_retries: this.llm_max_retries,
            llm_retry_base_delay: this.llm_retry_base_delay,
            llm_retry_max_delay: this.llm_retry_max_delay,
            llm_retryable_status_codes: this.llm_retryable_status_codes,
          })
        : await invokeLLMOnce({
            llm: this.llm,
            messages: this.messages,
            tools: this.tools,
            tool_definitions: this.tool_definitions,
            tool_choice: this.tool_choice,
            usage_tracker: this.usage_tracker,
          });

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

      await this.checkAndCompact(response);
    }

    return await generateMaxIterationsSummary({
      llm: this.llm,
      messages: this.messages,
      max_iterations: this.max_iterations,
    });
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
      await destroyEphemeralMessages({
        messages: this.messages,
        tool_map: this.tool_map,
        ephemeral_storage_path: this.ephemeral_storage_path,
      });

      const response = this.retry_enabled
        ? await invokeLLMWithRetries({
            llm: this.llm,
            messages: this.messages,
            tools: this.tools,
            tool_definitions: this.tool_definitions,
            tool_choice: this.tool_choice,
            usage_tracker: this.usage_tracker,
            llm_max_retries: this.llm_max_retries,
            llm_retry_base_delay: this.llm_retry_base_delay,
            llm_retry_max_delay: this.llm_retry_max_delay,
            llm_retryable_status_codes: this.llm_retryable_status_codes,
          })
        : await invokeLLMOnce({
            llm: this.llm,
            messages: this.messages,
            tools: this.tools,
            tool_definitions: this.tool_definitions,
            tool_choice: this.tool_choice,
            usage_tracker: this.usage_tracker,
          });

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
          const toolResult = await executeToolCall({
            tool_call: toolCall,
            tool_map: this.tool_map,
            dependency_overrides: this.dependency_overrides,
          });
          this.messages.push(toolResult);
          const screenshot = extractScreenshot(toolResult);
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

    const summary = await generateMaxIterationsSummary({
      llm: this.llm,
      messages: this.messages,
      max_iterations: this.max_iterations,
    });
    yield new FinalResponseEvent(summary);
  }
}
