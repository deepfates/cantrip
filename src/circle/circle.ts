import type { GateResult } from "./gate/gate";
import type { Ward } from "./ward";

/**
 * A Circle binds a set of Gates (tools) together with Wards (constraints).
 *
 * It represents the "capability envelope" of an Entity — what actions
 * it can take and what limits govern those actions.
 */
export interface Circle {
  /** The gates (tools) available within this circle. */
  gates: GateResult[];

  /** The wards (constraints) that govern execution within this circle. */
  wards: Ward[];
}

/**
 * Construct a Circle with validation.
 *
 * CIRCLE-1: Must have a gate named "done".
 * CIRCLE-2: Must have at least one ward with max_turns > 0.
 */
export function Circle(opts: { gates: GateResult[]; wards: Ward[] }): Circle {
  if (!opts.gates.some((g) => g.name === "done")) {
    throw new Error("Circle must have a done gate");
  }
  if (opts.wards.length === 0) {
    throw new Error("Circle must have at least one ward");
  }
  return { gates: opts.gates, wards: opts.wards };
}
