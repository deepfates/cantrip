/**
 * A Ward constrains an Entity's execution to prevent runaway behavior.
 *
 * Wards are safety boundaries extracted from what was previously
 * scattered across AgentOptions. They define the operational limits
 * within which an Entity operates.
 */
export type Ward = {
  /** Maximum number of agent loop iterations before forced termination. */
  max_turns: number;

  /** Whether the Entity must use a 'done' tool to terminate (vs. stopping on text response). */
  require_done_tool: boolean;
};

/** Default ward configuration. */
export const DEFAULT_WARD: Ward = {
  max_turns: 200,
  require_done_tool: false,
};

/** Create a ward that limits the number of turns. */
export function max_turns(n: number): Ward {
  return { max_turns: n, require_done_tool: false };
}

/** Create a ward that requires the done tool to terminate. */
export function require_done(max_turns?: number): Ward {
  return { max_turns: max_turns ?? 200, require_done_tool: true };
}
