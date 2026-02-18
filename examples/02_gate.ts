// Gate — define tools the entity can use.
// Gates are the actions available inside a circle. The `done` gate is required.

import { tool, done, TaskComplete } from "../src";

// Define a custom gate with the @tool decorator pattern.
const add = tool("Add two numbers", async ({ a, b }: { a: number; b: number }) => a + b, {
  name: "add",
  params: { a: "number", b: "number" },
});

async function main() {
  // Gates can be executed directly for testing.
  const sum = await add.execute({ a: 2, b: 3 });
  console.log("add(2, 3) =", sum);

  // The done gate signals completion. It throws TaskComplete internally.
  try {
    await done.execute({ result: "All done" });
  } catch (e) {
    if (e instanceof TaskComplete) {
      console.log("done gate fired:", e.message);
    }
  }
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
