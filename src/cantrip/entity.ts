import type { BaseChatModel } from "../crystal/crystal";
import type { AnyMessage } from "../crystal/messages";
import type { Call } from "./call";
import { Circle } from "../circle/circle";
import type { DependencyOverrides } from "../circle/gate/depends";
import type { BoundGate } from "../circle/gate";
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
import { recordCallRoot, recordTurn, checkAndFold } from "../entity/recording";
import type { Loom } from "../loom";
import type { FoldingConfig } from "../loom/folding";
import { DEFAULT_FOLDING_CONFIG } from "../loom/folding";
import {
  currentTurnIdBinding,
  spawnBinding,
  progressBinding,
  type SpawnFn,
} from "../circle/gate/builtin/call_entity_gate";

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
  /** Parent turn ID — when this entity is a child, the parent turn that spawned it. */
  parent_turn_id?: string | null;
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
 * creates an Entity that accumulates state across multiple `cast()` calls.
 *
 * Entity owns its circle state (messages) directly and uses `runLoop`
 * for both `cast()` (returns string) and `cast_stream()` (yields events).
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
  private tool_map: Map<string, BoundGate> = new Map();

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

  /** Parent turn ID — when this entity is a child, the parent turn that spawned it. */
  private parent_turn_id: string | null = null;

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
    this.usage_tracker = options.usage_tracker ?? new UsageTracker();
    this.loom = options.loom;
    this.cantrip_id = options.cantrip_id ?? crypto.randomUUID();
    this.entity_id = options.entity_id ?? crypto.randomUUID();
    this.parent_turn_id = options.parent_turn_id ?? null;
    this.folding = options.folding ?? DEFAULT_FOLDING_CONFIG;
    this.folding_enabled = options.folding_enabled ?? true;
    this.retry = options.retry;

    for (const gate of this.circle.gates) {
      this.tool_map.set(gate.name, gate);
    }

    // Auto-populate framework bindings for call_entity if that gate is present.
    // Framework bindings use Depends instances as Map keys, so we need a Map.
    // If the user passed a Record, convert entries to Map keyed by the factory function.
    const userOverrides = options.dependency_overrides;
    let overrides: DependencyOverrides | null = userOverrides ?? null;

    if (this.tool_map.has("call_entity")) {
      // Ensure we have a Map for framework bindings
      let bindingMap: Map<any, any>;
      if (userOverrides instanceof Map) {
        bindingMap = userOverrides;
      } else if (userOverrides && typeof userOverrides === "object") {
        // Convert Record overrides to Map (keyed by factory function for Depends.resolve)
        bindingMap = new Map();
        for (const [name, factory] of Object.entries(userOverrides)) {
          bindingMap.set(name, factory);
        }
      } else {
        bindingMap = new Map();
      }

      // currentTurnIdBinding: provide a getter that always reads current last_turn_id
      if (!bindingMap.has(currentTurnIdBinding)) {
        bindingMap.set(currentTurnIdBinding, () => () => this.last_turn_id);
      }
      // spawnBinding: provide a default spawn that creates a minimal child entity.
      // Callers can override via dependency_overrides for richer child configs.
      if (!bindingMap.has(spawnBinding)) {
        bindingMap.set(spawnBinding, (): SpawnFn => {
          return async (query: string, context: unknown): Promise<string> => {
            const contextStr = typeof context === "string"
              ? context
              : JSON.stringify(context, null, 2);
            const truncated = contextStr.length > 10000
              ? contextStr.slice(0, 10000) + "\n... [truncated]"
              : contextStr;
            // Minimal child: direct LLM query (no circle, no recursion)
            const res = await this.crystal.query([
              { role: "user", content: `Task: ${query}\n\nContext:\n${truncated}` },
            ]);
            if (res.usage) {
              this.usage_tracker.add(this.crystal.model, res.usage);
            }
            return res.content ?? "";
          };
        });
      }

      overrides = bindingMap;
    }

    this.dependency_overrides = overrides;
  }

  /** The ID of the last turn recorded in the loom. Used by call_entity to thread children. */
  get lastTurnId(): string | null {
    return this.last_turn_id;
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
   * Cast an intent: run the agent loop, return the result.
   * State accumulates — each cast sees all prior context.
   */
  async cast(intent: Intent): Promise<string> {
    return this._runLoop(intent);
  }

  /**
   * Cast an intent with streaming: yields TurnEvents as they occur.
   * State accumulates — each cast sees all prior context.
   */
  async *cast_stream(intent: Intent): AsyncGenerator<TurnEvent> {
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
      // Auto-prepend circle capability docs (medium physics + gate docs)
      // so the developer's Call string is pure strategy.
      const capDocs = this.circle.capabilityDocs();
      const systemContent = capDocs
        ? capDocs + "\n\n" + this.call.system_prompt
        : this.call.system_prompt;
      this.messages.push({
        role: "system",
        content: systemContent,
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
        parent_turn_id: this.parent_turn_id,
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
