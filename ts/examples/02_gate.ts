// Example 02: Gate
// A gate is a typed function the entity can call.
// Gates are how entities interact with the outside world.

import { gate, done, TaskComplete } from "../src";

const add = gate("Add two numbers", async ({ a, b }: { a: number; b: number }) => a + b, {
  name: "add",
  params: { a: "number", b: "number" },
});

export async function main() {
  console.log("=== Example 02: Gate ===");
  console.log("A gate is a typed function the entity can call.\n");

  // Gates can be executed directly — useful for testing.
  console.log("Calling add(2, 3)...");
  const sum = await add.execute({ a: 2, b: 3 });
  console.log(`Result: ${sum}`);

  // The done gate signals completion. It throws TaskComplete internally.
  console.log("\nCalling done gate...");
  let doneMessage: string | undefined;
  try {
    await done.execute({ message: "All done" });
  } catch (e) {
    if (e instanceof TaskComplete) {
      doneMessage = e.message;
      console.log(`done gate threw TaskComplete: "${doneMessage}"`);
    }
  }

  console.log("\nGates are just functions with metadata. The entity sees them as tools.");

  return { sum, doneMessage };
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
