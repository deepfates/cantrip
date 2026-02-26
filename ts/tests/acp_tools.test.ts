import { describe, expect, test } from "bun:test";
import { getToolKind, getToolLocations, getToolTitle } from "../src/acp/tools";

describe("ACP tool classification", () => {
  describe("getToolKind", () => {
    test("maps known tools to correct kinds", () => {
      expect(getToolKind("read")).toBe("read");
      expect(getToolKind("write")).toBe("edit");
      expect(getToolKind("edit")).toBe("edit");
      expect(getToolKind("bash")).toBe("execute");
      expect(getToolKind("glob")).toBe("search");
      expect(getToolKind("browser")).toBe("fetch");
      expect(getToolKind("browser_interactive")).toBe("fetch");
      expect(getToolKind("browser_readonly")).toBe("fetch");
      expect(getToolKind("js")).toBe("execute");
      expect(getToolKind("js_run")).toBe("execute");
      expect(getToolKind("done")).toBe("other");
    });

    test("returns 'other' for unknown tools", () => {
      expect(getToolKind("custom_tool")).toBe("other");
      expect(getToolKind("")).toBe("other");
    });
  });

  describe("getToolLocations", () => {
    test("extracts file_path from args", () => {
      const locations = getToolLocations("read", {
        file_path: "/src/index.ts",
      });
      expect(locations).toEqual([{ path: "/src/index.ts" }]);
    });

    test("extracts path from args as fallback", () => {
      const locations = getToolLocations("glob", { path: "/src" });
      expect(locations).toEqual([{ path: "/src" }]);
    });

    test("prefers file_path over path", () => {
      const locations = getToolLocations("read", {
        file_path: "/a.ts",
        path: "/b.ts",
      });
      expect(locations).toEqual([{ path: "/a.ts" }]);
    });

    test("returns empty array when no path in args", () => {
      expect(getToolLocations("bash", { command: "ls" })).toEqual([]);
      expect(getToolLocations("done", {})).toEqual([]);
    });

    test("returns empty array when path is not a string", () => {
      expect(getToolLocations("read", { file_path: 123 })).toEqual([]);
    });
  });

  describe("getToolTitle", () => {
    test("includes file path for file tools", () => {
      expect(getToolTitle("read", { file_path: "src/index.ts" })).toBe(
        "Reading src/index.ts",
      );
      expect(getToolTitle("write", { file_path: "out.txt" })).toBe(
        "Writing out.txt",
      );
      expect(getToolTitle("edit", { file_path: "foo.ts" })).toBe(
        "Editing foo.ts",
      );
    });

    test("uses fallback when no file_path", () => {
      expect(getToolTitle("read", {})).toBe("Reading file");
      expect(getToolTitle("write", {})).toBe("Writing file");
      expect(getToolTitle("edit", {})).toBe("Editing file");
    });

    test("shows command in bash title", () => {
      expect(getToolTitle("bash", { command: "ls" })).toBe("$ ls");
      expect(getToolTitle("bash", { command: "npm install && npm test" })).toBe(
        "$ npm install && npm test",
      );
      expect(getToolTitle("bash", {})).toBe("Running command");
    });

    test("shows first line of code in js title", () => {
      expect(getToolTitle("js", { code: "1+1" })).toBe("Running: 1+1");
      expect(getToolTitle("js_run", { code: "1+1" })).toBe("Running: 1+1");
      expect(getToolTitle("js", {})).toBe("Running JavaScript");
      expect(getToolTitle("js", { code: "" })).toBe("Running JavaScript");
      expect(getToolTitle("js", { code: "\n  const x = 1;\n" })).toBe(
        "Running: const x = 1;",
      );
    });

    test("returns fixed titles for other tools", () => {
      expect(getToolTitle("glob", { pattern: "*.ts" })).toBe("Searching files");
      expect(getToolTitle("browser", { url: "http://x" })).toBe("Browsing");
      expect(getToolTitle("browser_interactive", {})).toBe("Browsing");
      expect(getToolTitle("browser_readonly", {})).toBe("Browsing");
      expect(getToolTitle("done", {})).toBe("Completing task");
    });

    test("shows message preview for done tool", () => {
      expect(getToolTitle("done", { message: "Task completed!" })).toBe(
        "Done: Task completed!",
      );
      expect(
        getToolTitle("done", {
          message: "This is a very long message that should be truncated because it exceeds the maximum length",
        }),
      ).toBe(
        "Done: This is a very long message that should be truncated because...",
      );
    });

    test("returns tool name for unknown tools", () => {
      expect(getToolTitle("custom_tool", {})).toBe("custom_tool");
    });
  });
});
