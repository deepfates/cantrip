import { describe, test, expect } from "bun:test";
import { createJsRunTool, js_run } from "../src/tools/builtin/js_run";
import type { ToolContent } from "../src/tools/decorator";

describe("js_run tool", () => {
  function expectString(result: ToolContent): asserts result is string {
    if (typeof result !== "string") {
      throw new Error("Expected string tool output");
    }
  }

  test("executes simple code and returns the result", async () => {
    const result = await js_run.execute({ code: "export default 2 + 3" });
    expectString(result);
    expect(result).toBe("5");
  });

  test("does not persist state between calls", async () => {
    const first = await js_run.execute({
      code: "globalThis.x = 10; export default globalThis.x",
    });
    expectString(first);
    expect(first).toBe("10");

    const second = await js_run.execute({
      code: "export default typeof globalThis.x",
    });
    expectString(second);
    expect(second).toBe("undefined");
  });

  test("returns formatted errors", async () => {
    const result = await js_run.execute({ code: "function {" });
    expectString(result);
    expect(result.startsWith("Error:")).toBe(true);
  });

  test("supports virtual fs when mounted", async () => {
    const js_run_fs = createJsRunTool({
      allow_fs: true,
      mount_fs: { "note.txt": "hello" },
    });

    const result = await js_run_fs.execute({
      code: `
import { readFileSync } from "node:fs";
export default readFileSync("note.txt", "utf8");
      `.trim(),
    });
    expectString(result);
    expect(result).toBe("hello");
  });

  test("compute profile disables fetch", async () => {
    const js_run_compute = createJsRunTool({ profile: "compute" });
    const result = await js_run_compute.execute({
      code: `
let message = "no error";
try {
  await fetch("https://example.com");
} catch (e) {
  message = e?.message ?? String(e);
}
export default message;
      `.trim(),
    });
    expectString(result);
    expect(result.startsWith("Not supported: fetch")).toBe(true);
  });
});
