import type { BaseChatModel } from "../crystal/crystal";
import type { AnyMessage } from "../crystal/messages";
import type { Call } from "./call";
import { renderGateDefinitions } from "./call";
import type { Circle } from "../circle/circle";
import { resolveWards } from "../circle/ward";
import type { DependencyOverrides } from "../circle/gate/depends";
import type { GateResult } from "../circle/gate";
import type { Intent } from "./intent";
import { Entity } from "./entity";
import { UsageTracker } from "../crystal/tokens";
import {
  invokeLLMWithRetries,
  generateMaxIterationsSummary,
  runAgentLoop,
} from "../entity/runtime";

/**
 * A Cantrip is the minimal recipe for creating an Entity.
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
  call: CallInput;
  circle: Circle;
  /** Optional dependency overrides for gate DI (e.g., sandbox contexts). */
  dependency_overrides?: DependencyOverrides | null;
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

  const { crystal, call: callInput, circle, dependency_overrides } = input;

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
     * INTENT-2: intent becomes the first user message.
     *
     * Calls runAgentLoop directly — no Agent in the path.
     */
    async cast(intent: Intent): Promise<any> {
      // INTENT-1: intent is required
      if (!intent) {
        throw new Error("cast: intent is required (INTENT-1)");
      }

      // CANTRIP-2: fresh state per cast
      const ward = resolveWards(circle.wards);
      const tools = circle.gates;
      const tool_map = new Map<string, GateResult>();
      for (const tool of tools) {
        tool_map.set(tool.name, tool);
      }
      const effectiveToolChoice = ward.require_done_tool
        ? "required"
        : resolvedCall.hyperparameters.tool_choice;
      const hasExecInterface = typeof circle.crystalView === "function";
      const crystalView = hasExecInterface
        ? circle.crystalView(effectiveToolChoice)
        : null;
      const tool_definitions =
        crystalView?.tool_definitions ?? resolvedCall.gate_definitions;
      const viewToolChoice =
        crystalView?.tool_choice ?? effectiveToolChoice;
      const usage_tracker = new UsageTracker();
      const messages: AnyMessage[] = [];

      // System prompt first, then intent as first user message
      if (resolvedCall.system_prompt) {
        messages.push({
          role: "system",
          content: resolvedCall.system_prompt,
          cache: true,
        } as AnyMessage);
      }
      // INTENT-2: intent becomes the first user message
      messages.push({ role: "user", content: intent } as AnyMessage);

      return runAgentLoop({
        llm: crystal,
        tools,
        tool_map,
        tool_definitions,
        tool_choice: viewToolChoice,
        messages,
        system_prompt: resolvedCall.system_prompt,
        max_iterations: ward.max_turns,
        require_done_tool: ward.require_done_tool,
        dependency_overrides: dependency_overrides ?? null,
        ...(hasExecInterface ? { circle } : {}),
        invoke_llm: async () =>
          invokeLLMWithRetries({
            llm: crystal,
            messages,
            tools,
            tool_definitions,
            tool_choice: viewToolChoice,
            usage_tracker,
            llm_max_retries: 5,
            llm_retry_base_delay: 1.0,
            llm_retry_max_delay: 60.0,
            llm_retryable_status_codes: new Set([429, 500, 502, 503, 504]),
          }),
        on_max_iterations: async () =>
          generateMaxIterationsSummary({
            llm: crystal,
            messages,
            max_iterations: ward.max_turns,
          }),
      });
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
      });
    },
  };
}
