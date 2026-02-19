import type { BaseChatModel } from "../crystal/crystal";
import type { AnyMessage } from "../crystal/messages";
import type { Call } from "./call";
import { Circle } from "../circle/circle";
import type { DependencyOverrides } from "../circle/gate/depends";
import type { GateResult } from "../circle/gate";
import type { Intent } from "./intent";
import type { TurnEvent } from "../entity/events";
import { HiddenUserMessageEvent } from "../entity/events";
import { resolveWards } from "../circle/ward";
import { UsageTracker } from "../crystal/tokens";
import {
  destroyEphemeralMessages,
  invokeLLMWithRetries,
  generateMaxIterationsSummary,
  runLoop,
} from "../entity/runtime";
import { recordCallRoot, recordTurn, checkAndFold } from "../entity/service";
import type { Loom } from "../loom";
import type { FoldingConfig } from "../loom/folding";
import { DEFAULT_FOLDING_CONFIG } from "../loom/folding";

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
  /** Optional loom for recording turns. */
  loom?: Loom;
  /** Cantrip ID for loom recording. */
  cantrip_id?: string;
  /** Entity ID for loom recording. */
  entity_id?: string;
  /** Folding configuration. */
  folding?: FoldingConfig;
  /** Whether folding is enabled. */
  folding_enabled?: boolean;
  /** Retry configuration for LLM calls. */
  retry?: {
    max_retries?: number;
    base_delay?: number;
    max_delay?: number;
    retryable_status_codes?: Set<number>;
  };
};

/**
 * An Entity is a persistent multi-turn session created by invoking a Cantrip.
 *
 * While `cast()` is fire-and-forget (one intent → one result), `invoke()`
 * creates an Entity that accumulates state across multiple `turn()` calls.
 *
 * Entity owns its circle state (messages) directly and uses `runLoop`
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

  /** Optional loom for recording turns. */
  private loom?: Loom;

  /** Cantrip ID for loom recording. */
  private cantrip_id: string;

  /** Entity ID for loom recording. */
  private entity_id: string;

  /** Last turn ID in the loom (for parent chaining). */
  private last_turn_id: string | null = null;

  /** Folding configuration. */
  private folding: FoldingConfig;

  /** Whether folding is enabled. */
  private folding_enabled: boolean;

  /** Retry configuration. */
  private retry?: {
    max_retries?: number;
    base_delay?: number;
    max_delay?: number;
    retryable_status_codes?: Set<number>;
  };

  constructor(options: EntityOptions) {
    this.crystal = options.crystal;
    this.call = options.call;
    this.circle = options.circle;
    this.dependency_overrides = options.dependency_overrides;
    this.usage_tracker = options.usage_tracker ?? new UsageTracker();
    this.loom = options.loom;
    this.cantrip_id = options.cantrip_id ?? "unknown";
    this.entity_id = options.entity_id ?? "unknown";
    this.folding = options.folding ?? DEFAULT_FOLDING_CONFIG;
    this.folding_enabled = options.folding_enabled ?? false;
    this.retry = options.retry;

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
   * Execute a turn with streaming: yields TurnEvents as they occur.
   * State accumulates — each turn sees all prior context.
   */
  async *turn_stream(intent: Intent): AsyncGenerator<TurnEvent> {
    const events: TurnEvent[] = [];
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
    on_event?: (event: TurnEvent) => void,
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

    // CALL-4: Record the call as the loom root before the first turn
    if (this.loom && this.last_turn_id === null) {
      this.last_turn_id = await recordCallRoot({
        loom: this.loom,
        cantrip_id: this.cantrip_id,
        entity_id: this.entity_id,
        system_prompt: this.call.system_prompt,
        tool_definitions: crystalView?.tool_definitions ?? this.call.gate_definitions,
      });
    }

    return runLoop({
      llm: this.crystal,
      tools: this.circle.gates,
      circle: this.circle,
      messages: this.messages,
      system_prompt: this.call.system_prompt,
      max_iterations: ward.max_turns,
      require_done_tool: ward.require_done_tool,
      dependency_overrides: this.dependency_overrides ?? null,
      usage_tracker: this.usage_tracker,
      on_event,
      invoke_llm: async () =>
        invokeLLMWithRetries({
          llm: this.crystal,
          messages: this.messages,
          tools: this.circle.gates,
          tool_definitions,
          tool_choice: viewToolChoice,
          usage_tracker: this.usage_tracker,
          llm_max_retries: this.retry?.max_retries ?? 5,
          llm_retry_base_delay: this.retry?.base_delay ?? 1.0,
          llm_retry_max_delay: this.retry?.max_delay ?? 60.0,
          llm_retryable_status_codes: this.retry?.retryable_status_codes ?? new Set([429, 500, 502, 503, 504]),
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
      on_turn_complete: this.loom
        ? async (turnData) => {
            this.last_turn_id = await recordTurn({
              loom: this.loom!,
              parent_id: this.last_turn_id,
              cantrip_id: this.cantrip_id,
              entity_id: this.entity_id,
              turnData,
            });
          }
        : undefined,
      after_response: (this.loom && this.folding_enabled)
        ? async (response) => {
            const newMessages = await checkAndFold({
              messages: this.messages,
              loom: this.loom!,
              last_turn_id: this.last_turn_id!,
              folding: this.folding,
              folding_enabled: this.folding_enabled,
              llm: this.crystal,
              system_prompt: this.call.system_prompt,
              response,
            });
            if (newMessages) {
              this.messages = newMessages;
              return true;
            }
          }
        : undefined,
    });
  }
}
