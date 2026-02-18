// Circle — bind gates with wards.
// A circle defines the capability envelope: what gates are available,
// and what wards constrain execution.

import { Circle, done, tool, max_turns, require_done } from "../src";

const greet = tool("Say hello", async ({ name }: { name: string }) => `Hello, ${name}!`, {
  name: "greet",
  params: { name: "string" },
});

export function main() {
  // Circle validates: must have a done gate (CIRCLE-1) and at least one ward (CIRCLE-2).
  const circle = Circle({
    gates: [greet, done],
    wards: [max_turns(10)],
  });

  console.log("Gates:", circle.gates.map((g) => g.name));
  console.log("Wards:", circle.wards);

  // require_done() creates a ward that forces the entity to call done.
  const strict = Circle({
    gates: [greet, done],
    wards: [require_done(50)],
  });
  console.log("Strict ward:", strict.wards);

  // Missing done gate → throws
  try {
    Circle({ gates: [greet], wards: [max_turns(10)] });
  } catch (e: any) {
    console.log("Expected error:", e.message);
  }

  // No wards → throws
  try {
    Circle({ gates: [greet, done], wards: [] });
  } catch (e: any) {
    console.log("Expected error:", e.message);
  }
}

if (import.meta.main) {
  main();
}
