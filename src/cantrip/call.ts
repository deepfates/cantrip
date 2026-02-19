import type { ToolChoice, GateDefinition } from "../crystal/crystal";
import type { BoundGate } from "../circle/gate/gate";

/**
 * A Call defines the parameters for a single invocation of an Entity.
 *
 * It binds a system prompt (behavioral instructions) with hyperparameters
 * (LLM generation settings) and the set of gate definitions available
 * for tool use during the call.
 *
 * Per SPEC §3.1, the Call carries RENDERED gate definitions — the JSON
 * Schema representation suitable for sending to an LLM, not the executable
 * gate objects themselves.
 */
export type Call = {
  /** System prompt that shapes the Entity's behavior for this call. */
  system_prompt: string | null;

  /** LLM-level generation parameters. */
  hyperparameters: CallHyperparameters;

  /** Rendered gate definitions (JSON Schema form, not executable). */
  gate_definitions: GateDefinition[];
};

/**
 * Render executable gates into the JSON Schema definitions carried by a Call.
 * This strips the `execute()` function and ephemeral metadata, keeping only
 * the LLM-facing definition.
 */
export function renderGateDefinitions(gates: BoundGate[]): GateDefinition[] {
  return gates.map((g) => g.definition);
}

/**
 * Hyperparameters control how the Crystal (LLM) generates responses.
 */
export type CallHyperparameters = {
  /** How the LLM should choose tools: "auto", "required", "none", or a specific tool name. */
  tool_choice: ToolChoice;
};
