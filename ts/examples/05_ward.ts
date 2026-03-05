// Example 05: Ward
// Wards constrain the circle — max turns, require done, max depth.
// Multiple wards compose: most restrictive wins (min), require_done is OR.

import { max_turns, require_done, max_depth, resolveWards, DEFAULT_WARD, type Ward } from "../src";

export function main() {
  console.log("=== Example 05: Ward ===");
  console.log("Wards constrain the circle. Let's see how they compose.\n");

  console.log("Default ward (what you get with no overrides):");
  console.log(`  max_turns: ${DEFAULT_WARD.max_turns}`);
  console.log(`  require_done_tool: ${DEFAULT_WARD.require_done_tool}`);
  console.log(`  max_depth: ${DEFAULT_WARD.max_depth}`);

  const wards: Ward[] = [max_turns(10), require_done(), max_depth(3)];
  const resolved = resolveWards(wards);
  console.log("\nResolved from [max_turns(10), require_done(), max_depth(3)]:");
  console.log(`  max_turns: ${resolved.max_turns}`);
  console.log(`  require_done_tool: ${resolved.require_done_tool}`);
  console.log(`  max_depth: ${resolved.max_depth}`);

  // Wards compose — most restrictive wins for numeric values.
  console.log("\nWards compose — most restrictive wins:");
  const composed = resolveWards([max_turns(50), max_turns(10), max_turns(100)]);
  console.log(`  [50, 10, 100] → max_turns: ${composed.max_turns}`);

  // require_done is OR — any ward saying "yes" wins.
  const orWard = resolveWards([{ require_done_tool: false }, require_done()]);
  console.log(`  require_done [false, true] → ${orWard.require_done_tool}`);

  console.log("\nWards are partial objects that merge into a single ResolvedWard.");

  return { resolved, composedMaxTurns: composed.max_turns, orRequireDone: orWard.require_done_tool };
}

if (import.meta.main) {
  main();
}
