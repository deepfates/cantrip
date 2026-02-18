/**
 * A Ward constrains an Entity's execution to prevent runaway behavior.
 *
 * Wards are safety boundaries extracted from what was previously
 * scattered across AgentOptions. They define the operational limits
 * within which an Entity operates.
 *
 * Each ward field is optional — composition merges multiple partial
 * wards into a single ResolvedWard via min/union semantics.
 */
export type Ward = {
  /** Maximum number of agent loop iterations before forced termination. */
  max_turns?: number;

  /** Whether the Entity must use a 'done' tool to terminate (vs. stopping on text response). */
  require_done_tool?: boolean;

  /** Maximum recursion depth for nested entity spawning. */
  max_depth?: number;
};

/**
 * A fully-resolved ward with all fields filled in.
 * Produced by resolveWards() after merging and applying defaults.
 */
export type ResolvedWard = {
  max_turns: number;
  require_done_tool: boolean;
  max_depth: number;
};

/** Default ward configuration. */
export const DEFAULT_WARD: ResolvedWard = {
  max_turns: 200,
  require_done_tool: false,
  max_depth: Infinity,
};

/**
 * Resolve an array of partial wards into a single ResolvedWard.
 *
 * Composition rules:
 * - max_turns: minimum of all provided values (most restrictive)
 * - require_done_tool: true if ANY ward sets it (union/OR)
 * - max_depth: minimum of all provided values (most restrictive)
 * - Missing fields fall through to DEFAULT_WARD
 */
export function resolveWards(wards: Ward[]): ResolvedWard {
  let max_turns: number | undefined;
  let require_done_tool = false;
  let max_depth: number | undefined;

  for (const w of wards) {
    if (w.max_turns !== undefined) {
      max_turns = max_turns === undefined ? w.max_turns : Math.min(max_turns, w.max_turns);
    }
    if (w.require_done_tool === true) {
      require_done_tool = true;
    }
    if (w.max_depth !== undefined) {
      max_depth = max_depth === undefined ? w.max_depth : Math.min(max_depth, w.max_depth);
    }
  }

  return {
    max_turns: max_turns ?? DEFAULT_WARD.max_turns,
    require_done_tool,
    max_depth: max_depth ?? DEFAULT_WARD.max_depth,
  };
}

/** Create a ward that limits the number of turns. */
export function max_turns(n: number): Ward {
  return { max_turns: n };
}

/** Create a ward that requires the done tool to terminate. */
export function require_done(): Ward {
  return { require_done_tool: true };
}

/** Create a ward that limits recursion depth. */
export function max_depth(n: number): Ward {
  return { max_depth: n };
}
