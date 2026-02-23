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

  /** Gate names to remove from the circle. Union semantics: if ANY ward excludes a gate, it's excluded. */
  exclude_gates?: string[];
};

/**
 * A fully-resolved ward with all fields filled in.
 * Produced by resolveWards() after merging and applying defaults.
 */
export type ResolvedWard = {
  max_turns: number;
  require_done_tool: boolean;
  max_depth: number;
  exclude_gates: string[];
};

/** Default ward configuration. */
export const DEFAULT_WARD: ResolvedWard = {
  max_turns: 200,
  require_done_tool: false,
  max_depth: Infinity,
  exclude_gates: [],
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
  const excludedGates = new Set<string>();

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
    if (w.exclude_gates) {
      for (const name of w.exclude_gates) {
        excludedGates.add(name);
      }
    }
  }

  // The "done" gate is never excludable — the circle requires it (CIRCLE-1).
  excludedGates.delete("done");

  return {
    max_turns: max_turns ?? DEFAULT_WARD.max_turns,
    require_done_tool,
    max_depth: max_depth ?? DEFAULT_WARD.max_depth,
    exclude_gates: Array.from(excludedGates),
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

/** Create a ward that excludes a gate from the circle. */
export function exclude_gate(name: string): Ward {
  return { exclude_gates: [name] };
}
