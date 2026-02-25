// Example 21: Independent Axes
// The circle formula A = (M + G) - W has independent knobs.
// Same cantrip structure, different configurations — showing that medium,
// gates, and wards are orthogonal. Change one without touching the others.

import "./env";
import {
  cantrip, Circle, ChatAnthropic,
  max_turns, gate, done,
} from "../src";

// A gate that provides weather data
const weather = gate(
  "Get weather for a city",
  async ({ city }: { city: string }) => `${city}: 72°F, sunny`,
  { name: "weather", params: { city: "string" } },
);

// A gate that provides population data
const population = gate(
  "Get population of a city",
  async ({ city }: { city: string }) => `${city}: 1,234,567`,
  { name: "population", params: { city: "string" } },
);

export async function main() {
  console.log("=== Example 21: Independent Axes ===");
  console.log("A = (M + G) - W — each axis is an independent knob.\n");

  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });
  const intent = "Tell me about Seattle.";

  // ── Same medium, different gates (G as independent variable) ──────

  console.log("--- G axis: same medium, different gate sets ---");

  const weatherOnly = Circle({
    gates: [weather, done],
    wards: [max_turns(5)],
  });
  const bothGates = Circle({
    gates: [weather, population, done],
    wards: [max_turns(5)],
  });

  const weatherSpell = cantrip({
    crystal,
    call: "Answer using your tools. Call done with your answer.",
    circle: weatherOnly,
  });
  const bothSpell = cantrip({
    crystal,
    call: "Answer using your tools. Call done with your answer.",
    circle: bothGates,
  });

  const r1 = await weatherSpell.cast(intent);
  console.log(`Weather gates only: ${r1}`);

  const r2 = await bothSpell.cast(intent);
  console.log(`Weather + population: ${r2}\n`);

  // ── Same gates, different wards (W as independent variable) ───────

  console.log("--- W axis: same gates, different ward constraints ---");

  const loose = Circle({
    gates: [weather, population, done],
    wards: [max_turns(10)],
  });
  const tight = Circle({
    gates: [weather, population, done],
    wards: [max_turns(2)],  // very tight — may not finish
  });

  const looseSpell = cantrip({ crystal, call: "Use tools to answer. Call done with result.", circle: loose });
  const tightSpell = cantrip({ crystal, call: "Use tools to answer. Call done with result.", circle: tight });

  const r3 = await looseSpell.cast(intent);
  console.log(`10 turns allowed: ${r3}`);

  try {
    const r4 = await tightSpell.cast(intent);
    console.log(`2 turns allowed: ${r4}`);
  } catch (e: any) {
    console.log(`2 turns allowed: ward stopped it — ${e.message}`);
  }

  console.log("\nSame crystal, same call, same gates — wards change the outcome.");

  return { r1, r2, r3 };
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
