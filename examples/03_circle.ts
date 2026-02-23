// Example 03: Circle
// A circle = medium + gates + wards. It defines the entity's capability envelope.
// Circle validates: must have a done gate (CIRCLE-1) and at least one ward (CIRCLE-2).

import { Circle, done, gate, max_turns, require_done } from "../src";

const greet = gate("Say hello", async ({ name }: { name: string }) => `Hello, ${name}!`, {
  name: "greet",
  params: { name: "string" },
});

export function main() {
  console.log("=== Example 03: Circle ===");
  console.log("A circle = medium + gates + wards. It's the entity's sandbox.\n");

  // Basic circle: gates + wards.
  const circle = Circle({
    gates: [greet, done],
    wards: [max_turns(10)],
  });
  const gateNames = circle.gates.map((g) => g.name);
  console.log("Created circle with gates:", gateNames);
  console.log("Wards:", circle.wards);

  // require_done() creates a ward that forces the entity to call done.
  const strict = Circle({
    gates: [greet, done],
    wards: [require_done(), max_turns(50)],
  });
  console.log("\nStrict circle wards:", strict.wards);

  // Missing done gate → throws (CIRCLE-1).
  let missingDoneError: string | undefined;
  try {
    Circle({ gates: [greet], wards: [max_turns(10)] });
  } catch (e: any) {
    missingDoneError = e.message;
    console.log(`\nMissing done gate error: "${missingDoneError}"`);
  }

  // No wards → throws (CIRCLE-2).
  let noWardsError: string | undefined;
  try {
    Circle({ gates: [greet, done], wards: [] });
  } catch (e: any) {
    noWardsError = e.message;
    console.log(`No wards error: "${noWardsError}"`);
  }

  console.log("\nCircle enforces invariants: done gate required, wards required.");

  return { gateNames, missingDoneError, noWardsError };
}

if (import.meta.main) {
  main();
}
