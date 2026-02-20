/**
 * Test for ACP Browser example
 *
 * Verifies that the cantrip composition modules and browser context
 * can be imported and have the expected structure.
 */

import { describe, test, expect } from "bun:test";
import { cantrip } from "../src/cantrip/cantrip";
import { Circle } from "../src/circle/circle";
import { js } from "../src/circle/medium/js";
import { BrowserContext } from "../src/circle/medium/browser/context";

describe("ACP JS Browser Entity", () => {
  test("cantrip composition functions are defined", () => {
    expect(cantrip).toBeDefined();
    expect(typeof cantrip).toBe("function");
    expect(Circle).toBeDefined();
    expect(typeof Circle).toBe("function");
    expect(js).toBeDefined();
    expect(typeof js).toBe("function");
  });

  test("BrowserContext.create is defined", () => {
    expect(BrowserContext.create).toBeDefined();
    expect(typeof BrowserContext.create).toBe("function");
  });

  test("example file exists and is readable", async () => {
    const file = Bun.file("examples/13_acp.ts");
    expect(await file.exists()).toBe(true);
    const content = await file.text();
    expect(content).toContain("serveCantripACP");
    // ACP example uses JS medium (not browser-as-gate)
    expect(content).toContain("medium: js(");
  });
});
