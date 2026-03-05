/**
 * Turn record — the atomic unit of the loom.
 * See SPEC.md §6.1 for the full definition.
 */

/** Structured record of a completed gate invocation within a turn. */
export type GateCallRecord = {
  gate_name: string;
  arguments: string; // JSON-encoded arguments
  result: string;    // gate output (or error message)
  is_error: boolean;
};

/** Token and timing metadata for a turn. */
export type TurnMetadata = {
  tokens_prompt: number;
  tokens_completion: number;
  tokens_cached: number;
  duration_ms: number;
  timestamp: string; // ISO 8601
};

/**
 * A single turn in the loom tree.
 *
 * LOOM-1: Every turn MUST be recorded in the loom before the next turn begins.
 * LOOM-2: Each turn MUST have a unique ID and a reference to its parent.
 * LOOM-9: Each turn MUST record token usage and wall-clock duration.
 */
export type Turn = {
  id: string;
  parent_id: string | null; // null for root turns
  cantrip_id: string;
  entity_id: string;
  sequence: number; // position within this entity's run (0 for call root, 1+ for turns)

  /**
   * Turn role: "call" for the root turn recording the Call (CALL-4),
   * "turn" for regular entity turns. Defaults to "turn" when absent.
   */
  role?: "call" | "turn";

  utterance: string;   // what the entity said/wrote (system prompt for call roots)
  observation: string; // what the circle returned (gate definitions for call roots)

  gate_calls: GateCallRecord[];

  metadata: TurnMetadata;

  reward: number | null;   // reward signal, if assigned
  terminated: boolean;     // did this turn end with `done`?
  truncated: boolean;      // did a ward cut the entity off here?
};

/** Generate a unique turn ID. */
export function generateTurnId(): string {
  return `turn-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
}
