import { describe, expect, test } from "bun:test";
import { readFileSync } from "fs";
import path from "path";

describe("parity report", () => {
  test("PARITY.md exists with required sections", () => {
    const file = path.resolve(process.cwd(), "PARITY.md");
    const content = readFileSync(file, "utf8");
    const required = [
      "# Parity Checklist",
      "## Agent",
      "## Tools",
      "## LLM",
      "## Providers",
      "## Compaction",
      "## Tokens",
      "## Observability",
      "## Examples",
      "## Docs",
      "## Tests",
    ];
    for (const section of required) {
      expect(content.includes(section)).toBe(true);
    }
  });
});
