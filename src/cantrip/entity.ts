import type { BaseChatModel } from "../crystal/crystal";
import type { AnyMessage } from "../crystal/messages";
import type { Call } from "./call";
import type { Circle } from "../circle/circle";
import type { DependencyOverrides } from "../circle/gate/depends";
import type { GateResult } from "../circle/gate";
import type { Intent } from "./intent";
import type { AgentEvent } from "../entity/events";
import { HiddenUserMessageEvent } from "../entity/events";
import { resolveWards } from "../circle/ward";
import { UsageTracker } from "../crystal/tokens";
import {
  destroyEphemeralMessages,
  invokeLLMWithRetries,
  generateMaxIterationsSummary,
  runAgentLoop,
} from "../entity/runtime";

/**
 * Options for constructing an Entity.
 * Holds the spec parts (crystal, call, circle) — no Agent dependency.
 */
export type EntityOptions = {
  crystal: BaseChatModel;
  call: Call;
  circle: Circle;
  dependency_overrides: DependencyOverrides | null;
  /** Optional shared usage tracker (for aggregating across recursive entities). */
  usage_tracker?: UsageTracker;
};

/**
 * An Entity is a persistent multi-turn session created by invoking a Cantrip.
 *
 * While `cast()` is fire-and-forget (one intent → one result), `invoke()`
 * creates an Entity that accumulates state across multiple `turn()` calls.
 *
 * Entity owns its circle state (messages) directly and uses `runAgentLoop`
 * for both `turn()` (returns string) and `turn_stream()` (yields events).
 */
export class Entity {
  /** The Crystal (LLM) that powers this Entity. */
  readonly crystal: BaseChatModel;

  /** The resolved Call parameters. */
  readonly call: Call;

  /** The Circle of capabilities and constraints. */
  readonly circle: Circle;

  /** Dependency overrides for gate DI. */
  readonly dependency_overrides: DependencyOverrides | null;

  /** Circle state: the messages array the entity perceives. */
  private messages: AnyMessage[] = [];

  /** Tool lookup map, built once from circle gates. */
  private tool_map: Map<string, GateResult> = new Map();

  /** Tracks token usage across turns. */
  private usage_tracker: UsageTracker;

  constructor(options: EntityOptions) {
    this.crystal = options.crystal;
    this.call = options.call;
    this.circle = options.circle;
    this.dependency_overrides = options.dependency_overrides;
    this.usage_tracker = options.usage_tracker ?? new UsageTracker();

    for (const gate of this.circle.gates) {
      this.tool_map.set(gate.name, gate);
    }
  }

  /** Read-only snapshot of current message history. */
  get history(): AnyMessage[] {
    return [...this.messages];
  }

  /** Replace message history (for memory management / persistence). */
  load_history(messages: AnyMessage[]): void {
    this.messages = [...messages];
  }

  /** Get accumulated usage stats. */
  async get_usage() {
    return this.usage_tracker.getUsageSummary();
  }

  /**
   * Execute a turn: send an intent, run the agent loop, return the result.
   * State accumulates — each turn sees all prior context.
   */
  async turn(intent: Intent): Promise<string> {
    return this._runLoop(intent);
  }

  /**
   * Execute a turn with streaming: yields AgentEvents as they occur.
   * State accumulates — each turn sees all prior context.
   */
  async *turn_stream(intent: Intent): AsyncGenerator<AgentEvent> {
    const events: AgentEvent[] = [];
    let resolve: (() => void) | null = null;
    let done = false;
    let loopResult: string | undefined;
    let loopError: unknown;

    // The loop pushes events; the generator yields them.
    const loopPromise = this._runLoop(intent, (event) => {
      events.push(event);
      if (resolve) {
        resolve();
        resolve = null;
      }
    }).then(
      (result) => { loopResult = result; done = true; },
      (err) => { loopError = err; done = true; },
    );

    // Drain events as they arrive
    while (true) {
      // Yield any buffered events
      while (events.length > 0) {
        yield events.shift()!;
      }

      if (done) break;

      // Wait for more events or loop completion
      await new Promise<void>((r) => {
        resolve = r;
        // Also resolve when the loop finishes (in case no more events)
        loopPromise.then(r, r);
      });
    }

    // Yield any final events
    while (events.length > 0) {
      yield events.shift()!;
    }

    if (loopError) throw loopError;
  }

  /**
   * Internal: run the agent loop for a single turn.
   * Optionally accepts an on_event callback for streaming.
   */
  private async _runLoop(
    intent: Intent,
    on_event?: (event: AgentEvent) => void,
  ): Promise<string> {
    const ward = resolveWards(this.circle.wards);
    const effectiveToolChoice = ward.require_done_tool
      ? "required"
      : this.call.hyperparameters.tool_choice;

    // Initialize system prompt if this is a fresh conversation
    if (!this.messages.length && this.call.system_prompt) {
      this.messages.push({
        role: "system",
        content: this.call.system_prompt,
        cache: true,
      } as AnyMessage);
    }

    // INTENT-2: intent becomes a user message
    this.messages.push({ role: "user", content: intent } as AnyMessage);

    // Circle provides crystalView when constructed via Circle()
    const crystalView = this.circle.crystalView?.(effectiveToolChoice);
    const tool_definitions = crystalView?.tool_definitions ?? this.call.gate_definitions;
    const viewToolChoice = crystalView?.tool_choice ?? effectiveToolChoice;

    return runAgentLoop({
      llm: this.crystal,
      tools: this.circle.gates,
      tool_map: this.tool_map,
      tool_definitions,
      tool_choice: viewToolChoice,
      messages: this.messages,
      system_prompt: this.call.system_prompt,
      max_iterations: ward.max_turns,
      require_done_tool: ward.require_done_tool,
      dependency_overrides: this.dependency_overrides ?? null,
      usage_tracker: this.usage_tracker,
      on_event,
      ...(this.circle.execute ? { circle: this.circle } : {}),
      invoke_llm: async () =>
        invokeLLMWithRetries({
          llm: this.crystal,
          messages: this.messages,
          tools: this.circle.gates,
          tool_definitions,
          tool_choice: viewToolChoice,
          usage_tracker: this.usage_tracker,
          llm_max_retries: 5,
          llm_retry_base_delay: 1.0,
          llm_retry_max_delay: 60.0,
          llm_retryable_status_codes: new Set([429, 500, 502, 503, 504]),
        }),
      on_max_iterations: async () =>
        generateMaxIterationsSummary({
          llm: this.crystal,
          messages: this.messages,
          max_iterations: ward.max_turns,
        }),
      before_step: async () => {
        await destroyEphemeralMessages({
          messages: this.messages,
          tool_map: this.tool_map,
        });
      },
    });
  }
}
