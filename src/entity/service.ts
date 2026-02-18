import type { BaseChatModel, ToolChoice, GateDefinition } from "../crystal/crystal";
import type {
  AnyMessage,
  AssistantMessage,
  ToolMessage,
} from "../crystal/messages";
import { extractToolMessageText } from "../crystal/messages";
import type { ChatInvokeCompletion } from "../crystal/views";
import { hasGateCalls } from "../crystal/views";
import type { GateResult } from "../circle/gate";
import type { DependencyOverrides } from "../circle/gate/depends";
import type { Circle } from "../circle/circle";
import { DEFAULT_WARD, resolveWards } from "../circle/ward";
import {
  fold,
  shouldFold,
  partitionForFolding,
  type FoldingConfig,
  DEFAULT_FOLDING_CONFIG,
} from "../loom/folding";
import { deriveThread } from "../loom/thread";
import type { PricingProvider } from "../crystal/tokens";
import { UsageTracker } from "../crystal/tokens";
import { TaskComplete } from "./errors";
import type { Loom } from "../loom/loom";
import { generateTurnId } from "../loom/turn";
import type { Turn } from "../loom/turn";
import {
  destroyEphemeralMessages,
  executeToolCall,
  extractScreenshot,
  generateMaxIterationsSummary,
  invokeLLMOnce,
  invokeLLMWithRetries,
  runAgentLoop,
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
  UsageEvent,
} from "./events";

export { TaskComplete } from "./errors";

export type AgentOptions = {
  llm: BaseChatModel;
  tools?: GateResult[];
  system_prompt?: string | null;
  max_iterations?: number;
  tool_choice?: ToolChoice;
  folding?: Partial<FoldingConfig> | null;
  pricing_provider?: PricingProvider | null;
  dependency_overrides?: DependencyOverrides | null;
  ephemeral_storage_path?: string | null;
  require_done_tool?: boolean;
  llm_max_retries?: number;
  llm_retry_base_delay?: number;
  llm_retry_max_delay?: number;
  llm_retryable_status_codes?: Set<number> | number[];
  retry?: { enabled?: boolean };
  ephemerals?: { enabled?: boolean };
  folding_enabled?: boolean;
  usage_tracker?: UsageTracker;
  loom?: Loom | null;
  cantrip_id?: string;
  entity_id?: string;
  /**
   * Alternative to `tools` + ad-hoc options: provide a Circle that bundles
   * gates and wards together. When set, gates are used as `tools` and ward
   * constraints override `max_iterations` / `require_done_tool`.
   * The flat options still work for backward compatibility.
   */
  circle?: Circle | null;
};

export class Agent {
  llm: BaseChatModel;
  tools: GateResult[];
  system_prompt: string | null;
  max_iterations: number;
  tool_choice: ToolChoice;
  folding: FoldingConfig;
  pricing_provider: PricingProvider | null;
  dependency_overrides: DependencyOverrides | null;
  ephemeral_storage_path: string | null;
  require_done_tool: boolean;
  llm_max_retries: number;
  llm_retry_base_delay: number;
  llm_retry_max_delay: number;
  llm_retryable_status_codes: Set<number>;
  retry_enabled: boolean;
  ephemerals_enabled: boolean;
  folding_enabled: boolean;

  private messages: AnyMessage[] = [];
  private tool_map: Map<string, GateResult> = new Map();
  private usage_tracker: UsageTracker;
  private loom: Loom | null;
  private cantrip_id: string;
  private entity_id: string;
  private last_turn_id: string | null = null;

  constructor(options: AgentOptions) {
    // When a Circle is provided, extract gates and ward constraints from it.
    // Explicit options (tools, max_iterations, require_done_tool) take precedence.
    const circle = options.circle ?? null;
    const ward = resolveWards(circle?.wards ?? []);

    this.llm = options.llm;
    this.tools = options.tools ?? circle?.gates ?? [];
    this.system_prompt = options.system_prompt ?? null;
    this.max_iterations = options.max_iterations ?? ward.max_turns;
    this.tool_choice = options.tool_choice ?? "auto";
    this.folding = { ...DEFAULT_FOLDING_CONFIG, ...options.folding };
    this.pricing_provider = options.pricing_provider ?? null;
    this.dependency_overrides = options.dependency_overrides ?? null;
    this.ephemeral_storage_path = options.ephemeral_storage_path ?? null;
    this.require_done_tool = options.require_done_tool ?? ward.require_done_tool;
    this.llm_max_retries = options.llm_max_retries ?? 5;
    this.llm_retry_base_delay = options.llm_retry_base_delay ?? 1.0;
    this.llm_retry_max_delay = options.llm_retry_max_delay ?? 60.0;
    this.llm_retryable_status_codes = new Set(
      options.llm_retryable_status_codes ?? [429, 500, 502, 503, 504],
    );
    this.retry_enabled = options.retry?.enabled ?? true;
    this.ephemerals_enabled = options.ephemerals?.enabled ?? true;
    this.folding_enabled = options.folding_enabled ?? true;

    for (const tool of this.tools) {
      this.tool_map.set(tool.name, tool);
    }

    this.usage_tracker = options.usage_tracker ?? new UsageTracker();
    this.loom = options.loom ?? null;
    this.cantrip_id = options.cantrip_id ?? "default";
    this.entity_id = options.entity_id ?? "default";
  }

  get tool_definitions(): GateDefinition[] {
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

  /**
   * Record the Call as the loom root turn (CALL-4).
   * The system prompt, hyperparameters, and gate definitions are stored
   * as the root of the turn tree. Every thread starts from this turn.
   */
  private async recordCallRoot(): Promise<void> {
    if (!this.loom || this.last_turn_id !== null) return; // already recorded or no loom

    const gateDefinitions = this.tool_definitions
      .map((g) => `- ${g.function.name}: ${g.function.description ?? "(no description)"}`)
      .join("\n");

    const turn: Turn = {
      id: generateTurnId(),
      parent_id: null,
      cantrip_id: this.cantrip_id,
      entity_id: this.entity_id,
      sequence: 0,
      role: "call",
      utterance: this.system_prompt ?? "",
      observation: gateDefinitions,
      gate_calls: [],
      metadata: {
        tokens_prompt: 0,
        tokens_completion: 0,
        tokens_cached: 0,
        duration_ms: 0,
        timestamp: new Date().toISOString(),
      },
      reward: null,
      terminated: false,
      truncated: false,
    };

    await this.loom.append(turn);
    this.last_turn_id = turn.id;
  }

  /** Record a turn in the loom (LOOM-1). */
  private async recordTurn(turnData: {
    iteration: number;
    utterance: string;
    observation: string;
    gate_calls: { gate_name: string; arguments: string; result: string; is_error: boolean }[];
    usage: any;
    duration_ms: number;
    terminated: boolean;
    truncated: boolean;
  }): Promise<void> {
    if (!this.loom) return;
    const turn: Turn = {
      id: generateTurnId(),
      parent_id: this.last_turn_id,
      cantrip_id: this.cantrip_id,
      entity_id: this.entity_id,
      sequence: turnData.iteration,
      utterance: turnData.utterance,
      observation: turnData.observation,
      gate_calls: turnData.gate_calls,
      metadata: {
        tokens_prompt: turnData.usage?.prompt_tokens ?? 0,
        tokens_completion: turnData.usage?.completion_tokens ?? 0,
        tokens_cached: turnData.usage?.prompt_cached_tokens ?? 0,
        duration_ms: turnData.duration_ms,
        timestamp: new Date().toISOString(),
      },
      reward: null,
      terminated: turnData.terminated,
      truncated: turnData.truncated,
    };
    await this.loom.append(turn);
    this.last_turn_id = turn.id;
  }

  /**
   * Check whether folding should trigger and, if so, fold older turns.
   * Uses the loom's fold() API (LOOM-5: non-destructive).
   */
  private async checkAndFold(
    response: ChatInvokeCompletion,
  ): Promise<boolean> {
    if (!this.folding_enabled || !this.loom || !this.last_turn_id) return false;

    const totalTokens =
      (response.usage?.prompt_tokens ?? 0) +
      (response.usage?.completion_tokens ?? 0);

    // Use a default context window; pricing provider lookup could be added later
    const contextWindow = 128_000;
    if (!shouldFold(totalTokens, contextWindow, this.folding)) return false;

    // Derive the current thread from the loom and partition for folding
    const thread = deriveThread(this.loom, this.last_turn_id);
    const { toFold, toKeep } = partitionForFolding(thread, this.folding);
    if (toFold.length === 0) return false;

    const result = await fold(toFold, toKeep, this.llm, this.folding);
    if (!result.folded) return false;

    // Rebuild messages: keep system prompt + fold summary + recent turns as messages
    const newMessages: AnyMessage[] = [];
    if (this.system_prompt) {
      newMessages.push({
        role: "system",
        content: this.system_prompt,
        cache: true,
      } as AnyMessage);
    }
    newMessages.push(...result.messages);

    this.messages = newMessages;
    return true;
  }

  async query(message: string): Promise<string> {
    // CALL-4: Record the call as the loom root before the first turn
    await this.recordCallRoot();

    // Add system prompt first if this is a fresh conversation
    if (!this.messages.length && this.system_prompt) {
      this.messages.push({
        role: "system",
        content: this.system_prompt,
        cache: true,
      } as AnyMessage);
    }

    this.messages.push({ role: "user", content: message } as AnyMessage);

    let incomplete_todos_prompted = false;
    const effectiveToolChoice = this.require_done_tool
      ? "required"
      : this.tool_choice;

    const result = await runAgentLoop({
      llm: this.llm,
      tools: this.tools,
      tool_map: this.tool_map,
      tool_definitions: this.tool_definitions,
      tool_choice: effectiveToolChoice,
      messages: this.messages,
      system_prompt: this.system_prompt,
      max_iterations: this.max_iterations,
      require_done_tool: this.require_done_tool,
      dependency_overrides: this.dependency_overrides,
      before_step: async () => {
        if (this.ephemerals_enabled) {
          await destroyEphemeralMessages({
            messages: this.messages,
            tool_map: this.tool_map,
            ephemeral_storage_path: this.ephemeral_storage_path,
          });
        }
      },
      invoke_llm: async () =>
        this.retry_enabled
          ? await invokeLLMWithRetries({
              llm: this.llm,
              messages: this.messages,
              tools: this.tools,
              tool_definitions: this.tool_definitions,
              tool_choice: effectiveToolChoice,
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
              tool_choice: effectiveToolChoice,
              usage_tracker: this.usage_tracker,
            }),
      after_response: async (response, context) => {
        if (!context.has_tool_calls && !this.require_done_tool) {
          if (!incomplete_todos_prompted) {
            const prompt = await this.get_incomplete_todos_prompt();
            if (prompt) {
              incomplete_todos_prompted = true;
              this.messages.push({
                role: "user",
                content: prompt,
              } as AnyMessage);
              return true;
            }
          }
        }
        await this.checkAndFold(response);
        return false;
      },
      on_max_iterations: async () =>
        generateMaxIterationsSummary({
          llm: this.llm,
          messages: this.messages,
          max_iterations: this.max_iterations,
        }),
      on_turn_complete: this.loom
        ? async (turnData) => this.recordTurn(turnData)
        : undefined,
    });
    return result;
  }

  async *query_stream(message: string): AsyncGenerator<AgentEvent> {
    // CALL-4: Record the call as the loom root before the first turn
    await this.recordCallRoot();

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
    const effectiveToolChoice = this.require_done_tool
      ? "required"
      : this.tool_choice;

    while (iterations < this.max_iterations) {
      iterations += 1;
      if (this.ephemerals_enabled) {
        await destroyEphemeralMessages({
          messages: this.messages,
          tool_map: this.tool_map,
          ephemeral_storage_path: this.ephemeral_storage_path,
        });
      }

      const response = this.retry_enabled
        ? await invokeLLMWithRetries({
            llm: this.llm,
            messages: this.messages,
            tools: this.tools,
            tool_definitions: this.tool_definitions,
            tool_choice: effectiveToolChoice,
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
            tool_choice: effectiveToolChoice,
            usage_tracker: this.usage_tracker,
          });

      if (response.thinking) {
        yield new ThinkingEvent(response.thinking);
      }

      // Emit usage event after each LLM call
      if (response.usage) {
        const summary = await this.usage_tracker.getUsageSummary();
        yield new UsageEvent({
          prompt_tokens: response.usage.prompt_tokens,
          completion_tokens: response.usage.completion_tokens,
          total_tokens:
            response.usage.prompt_tokens + response.usage.completion_tokens,
          cached_tokens: response.usage.prompt_cached_tokens ?? 0,
          cumulative_tokens: summary.total_tokens,
        });
      }

      const assistantMessage: AssistantMessage = {
        role: "assistant",
        content: response.content ?? null,
        tool_calls: response.tool_calls ?? null,
      };
      this.messages.push(assistantMessage);

      if (!hasGateCalls(response)) {
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
          await this.checkAndFold(response);
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

      await this.checkAndFold(response);
    }

    const summary = await generateMaxIterationsSummary({
      llm: this.llm,
      messages: this.messages,
      max_iterations: this.max_iterations,
    });
    yield new FinalResponseEvent(summary);
  }
}
