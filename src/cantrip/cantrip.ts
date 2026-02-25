import type { BaseChatModel } from "../crystal/crystal";
import type { Call } from "./call";
import { renderGateDefinitions } from "./call";
import { Circle } from "../circle/circle";
import type { DependencyOverrides } from "../circle/gate/depends";
import type { Intent } from "./intent";
import { Entity } from "./entity";
import { UsageTracker } from "../crystal/tokens";
import { Loom, MemoryStorage } from "../loom";
import type { FoldingConfig } from "../loom/folding";

/**
 * A Cantrip is the minimal script for creating an Entity.
 *
 * It combines:
 * - A Crystal (LLM) — the intelligence that powers reasoning
 * - A Call — the invocation parameters (prompt, hyperparameters, gates)
 * - A Circle — the capability envelope (gates + wards)
 *
 * The name "cantrip" comes from the simplest spell in tabletop RPGs:
 * a spell so basic it requires no resources to cast. Similarly, a Cantrip
 * is the simplest configuration needed to bring an Entity to life.
 */
export type Cantrip = {
  /** The Crystal (LLM) that powers this Entity's reasoning. */
  crystal: BaseChatModel;

  /** The Call parameters for invocation. */
  call: Call;

  /** The Circle of capabilities and constraints. */
  circle: Circle;

  /** Cast the cantrip with an intent, producing an independent entity run. */
  cast(intent: Intent): Promise<any>;

  /** Invoke the cantrip to create a persistent Entity for multi-turn sessions. */
  invoke(): Entity;
};

/**
 * Partial call input — the user-friendly form where only system_prompt is required.
 * gate_definitions are derived from the circle, hyperparameters default to auto.
 */
export type CallInput = {
  system_prompt: string | null;
  hyperparameters?: { tool_choice?: "auto" | "required" | "none" | string };
  gate_definitions?: any[];
};

export type CantripInput = {
  crystal: BaseChatModel;
  call: string | CallInput;
  circle: Circle;
  /** Optional dependency overrides for gate DI (e.g., sandbox contexts). */
  dependency_overrides?: DependencyOverrides | null;
  /** Optional loom for recording turns. */
  loom?: Loom;
  /** Cantrip ID for loom recording. */
  cantrip_id?: string;
  /** Parent turn ID — when this entity is a child, the parent turn that spawned it. */
  parent_turn_id?: string | null;
  /** Folding configuration. */
  folding?: FoldingConfig;
  /** Whether folding is enabled. */
  folding_enabled?: boolean;
  /** Optional shared usage tracker (for aggregating across recursive entities). */
  usage_tracker?: UsageTracker;
  /** Retry configuration for LLM calls. */
  retry?: {
    max_retries?: number;
    base_delay?: number;
    max_delay?: number;
    retryable_status_codes?: Set<number>;
  };
};

/**
 * Factory function that creates a Cantrip — the primary public API.
 *
 * Validates:
 * - CANTRIP-1: crystal, call, and circle are all required
 * - CANTRIP-3: circle must have a done gate and at least one ward
 */
export function cantrip(input: CantripInput): Cantrip {
  // CANTRIP-1: all three are required
  if (!input.crystal) {
    throw new Error("cantrip: crystal is required");
  }
  if (!input.call) {
    throw new Error("cantrip: call is required");
  }
  if (!input.circle) {
    throw new Error("cantrip: circle is required");
  }

  // Normalize string shorthand: "prompt" → { system_prompt: "prompt" }
  const callInput: CallInput =
    typeof input.call === "string" ? { system_prompt: input.call } : input.call;
  const { crystal, circle, dependency_overrides } = input;

  // CANTRIP-3: circle must have at least one ward
  if (!circle.wards || circle.wards.length === 0) {
    throw new Error("cantrip: circle must have at least one ward (CANTRIP-3)");
  }

  // CANTRIP-3: circle must have a done gate (relaxed when medium handles termination)
  const hasDoneGate = circle.gates.some((g) => g.name === "done");
  if (!hasDoneGate && !circle.hasMedium) {
    throw new Error("cantrip: circle must have a done gate (CANTRIP-3)");
  }

  // Resolve the full Call from partial input
  const resolvedCall: Call = {
    system_prompt: callInput.system_prompt,
    hyperparameters: {
      tool_choice: callInput.hyperparameters?.tool_choice ?? "auto",
    },
    gate_definitions:
      callInput.gate_definitions ?? renderGateDefinitions(circle.gates),
  };

  return {
    crystal,
    call: resolvedCall,
    circle,

    /**
     * Cast the cantrip with an intent.
     * CANTRIP-2: each cast creates a fresh run — no shared state.
     * INTENT-1: intent is required.
     * LOOM-1: every turn is recorded via Entity's loom integration.
     * PROD-4: folding enabled by default.
     *
     * Creates a temporary Entity and calls cast() — Entity already handles
     * loom recording, folding, and the full run loop.
     */
    async cast(intent: Intent): Promise<any> {
      // INTENT-1: intent is required
      if (!intent) {
        throw new Error("cast: intent is required (INTENT-1)");
      }

      // CANTRIP-2: fresh state per cast — temporary Entity with fresh loom
      const entity = new Entity({
        crystal,
        call: resolvedCall,
        circle,
        dependency_overrides: dependency_overrides ?? null,
        loom: input.loom ?? new Loom(new MemoryStorage()),
        cantrip_id: input.cantrip_id,
        parent_turn_id: input.parent_turn_id,
        folding: input.folding,
        folding_enabled: input.folding_enabled ?? true,
        usage_tracker: input.usage_tracker,
        retry: input.retry,
      });

      try {
        return await entity.cast(intent);
      } finally {
        await entity.dispose();
      }
    },

    /**
     * Invoke the cantrip to create a persistent Entity.
     * CANTRIP-2: each invoke creates a fresh, independent Entity.
     */
    invoke(): Entity {
      return new Entity({
        crystal,
        call: resolvedCall,
        circle,
        dependency_overrides: dependency_overrides ?? null,
        loom: input.loom ?? new Loom(new MemoryStorage()),
        cantrip_id: input.cantrip_id,
        parent_turn_id: input.parent_turn_id,
        folding: input.folding,
        folding_enabled: input.folding_enabled ?? true,
        usage_tracker: input.usage_tracker,
        retry: input.retry,
      });
    },
  };
}
