// Example 19: Bash Medium (primary)
// The entity works IN bash — not delegating to it, but living in it.
// This is the ypi pattern: the shell is the medium, not a tool.
// Compare with the Familiar which delegates TO bash children.

import "./env";
import { cantrip, Circle, ChatAnthropic, max_turns, require_done, bash } from "../src";

export async function main() {
  console.log("=== Example 19: Bash Medium ===");
  console.log("The entity works inside a bash shell as its primary medium.");
  console.log("Shell commands are the thinking substrate.\n");

  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });

  const circle = Circle({
    medium: bash({ cwd: process.cwd() }),
    wards: [max_turns(10), require_done()],
  });

  const spell = cantrip({
    crystal,
    call: "You work in a bash shell. Use shell commands to explore and answer questions. Use submit_answer <result> when done.",
    circle,
  });

  try {
    console.log('Asking: "How many TypeScript files are in the src directory?"');
    const answer = await spell.cast("How many TypeScript files are in the src directory? Count them.");
    console.log(`Answer: ${answer}`);
    return answer;
  } finally {
    await circle.dispose?.();
  }
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
