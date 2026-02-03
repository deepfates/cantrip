import { describe, it, expect, beforeEach, afterEach } from "bun:test";
import {
  SandboxContext,
  read,
  write,
  bash,
  glob,
  edit,
  getSandboxContextDepends
} from "../src/tools/examples/fs";
import * as fs from "fs/promises";
import * as path from "path";

describe("File System Windowing", () => {
  let sandbox: SandboxContext;
  let testDir: string;
  let deps: any;

  beforeEach(async () => {
    testDir = path.join(process.cwd(), "tmp", "test-windowing");
    await fs.mkdir(testDir, { recursive: true });
    sandbox = new SandboxContext(testDir, testDir);
    deps = new Map([[getSandboxContextDepends, () => sandbox]]);
  });

  afterEach(async () => {
    await fs.rm(testDir, { recursive: true, force: true });
  });

  describe("read tool", () => {
    it("shows line range metadata", async () => {
      const content = Array.from({ length: 500 }, (_, i) => `line ${i + 1}`).join("\n");
      await write.execute({ file_path: "test.txt", content }, deps);

      const result = await read.execute({ file_path: "test.txt" }, deps);

      expect(result).toMatch(/^Lines 1-300 of 500/);
    });

    it("supports start_line parameter", async () => {
      const content = Array.from({ length: 100 }, (_, i) => `line ${i + 1}`).join("\n");
      await write.execute({ file_path: "test.txt", content }, deps);

      const result = await read.execute(
        { file_path: "test.txt", start_line: 50 },
        deps
      );

      expect(result).toMatch(/^Lines 50-100 of 100/);
      expect(result).toContain("  50  line 50");
    });

    it("supports max_lines parameter", async () => {
      const content = Array.from({ length: 100 }, (_, i) => `line ${i + 1}`).join("\n");
      await write.execute({ file_path: "test.txt", content }, deps);

      const result = await read.execute(
        { file_path: "test.txt", max_lines: 10 },
        deps
      );

      expect(result).toMatch(/^Lines 1-10 of 100/);
    });

    it("truncates very long lines", async () => {
      const longLine = "x".repeat(1000);
      await write.execute({ file_path: "test.txt", content: longLine }, deps);

      const result = await read.execute({ file_path: "test.txt" }, deps);

      expect(result).toContain("[line truncated");
      expect(result.length).toBeLessThan(10000);
    });

    it("detects binary files", async () => {
      const buffer = Buffer.from([0x00, 0x01, 0x02, 0xFF]);
      await fs.writeFile(path.join(testDir, "binary.bin"), buffer);

      const result = await read.execute({ file_path: "binary.bin" }, deps);

      expect(result).toContain("Binary file detected");
    });

    it("handles start_line beyond EOF", async () => {
      await write.execute({ file_path: "test.txt", content: "line 1\nline 2" }, deps);

      const result = await read.execute(
        { file_path: "test.txt", start_line: 100 },
        deps
      );

      expect(result).toContain("empty - file has 2 lines");
    });
  });

  describe("bash tool", () => {
    it("truncates long output", async () => {
      const result = await bash.execute(
        { command: `node -e "console.log('x'.repeat(15000))"` },
        deps
      );

      expect(result).toContain("[output truncated");
      expect(result.length).toBeLessThan(10000);
    });

    it("rejects commands over 5000 chars", async () => {
      const longCommand = "echo " + "x".repeat(6000);

      const result = await bash.execute({ command: longCommand }, deps);

      expect(result).toContain("Command too long");
    });

    it("supports max_output_chars parameter", async () => {
      const result = await bash.execute(
        { command: `node -e "console.log('x'.repeat(5000))"`, max_output_chars: 100 },
        deps
      );

      expect(result.length).toBeLessThan(200);
    });
  });

  describe("write tool", () => {
    it("rejects content over 50k chars", async () => {
      const bigContent = "x".repeat(60000);

      const result = await write.execute(
        { file_path: "test.txt", content: bigContent },
        deps
      );

      expect(result).toContain("Content too large");
    });

    it("accepts content under 50k", async () => {
      const content = "x".repeat(40000);

      const result = await write.execute(
        { file_path: "test.txt", content },
        deps
      );

      expect(result).toContain("Wrote 40000 bytes");
    });
  });

  describe("edit tool", () => {
    it("rejects search string over 10k", async () => {
      await write.execute({ file_path: "test.txt", content: "hello" }, deps);

      const result = await edit.execute(
        {
          file_path: "test.txt",
          old_string: "x".repeat(11000),
          new_string: "y"
        },
        deps
      );

      expect(result).toContain("Search string too large");
    });

    it("rejects replacement string over 10k", async () => {
      await write.execute({ file_path: "test.txt", content: "hello" }, deps);

      const result = await edit.execute(
        {
          file_path: "test.txt",
          old_string: "hello",
          new_string: "x".repeat(11000)
        },
        deps
      );

      expect(result).toContain("Replacement string too large");
    });
  });

  describe("glob tool", () => {
    beforeEach(async () => {
      // Create test files
      for (let i = 0; i < 150; i++) {
        await write.execute(
          { file_path: `file${i}.txt`, content: "test" },
          deps
        );
      }
    });

    it("shows pagination metadata", async () => {
      const result = await glob.execute({ pattern: "*.txt" }, deps);

      expect(result).toMatch(/^Results 0-99 of 150/);
    });

    it("supports offset parameter", async () => {
      const result = await glob.execute(
        { pattern: "*.txt", offset: 100 },
        deps
      );

      expect(result).toMatch(/^Results 100-149 of 150/);
      // Files are sorted alphabetically, so offset 100 will be around file5x-6x range
      expect(result.split('\n').length).toBeGreaterThan(40); // Should have ~50 results
    });

    it("supports max_results parameter", async () => {
      const result = await glob.execute(
        { pattern: "*.txt", max_results: 10 },
        deps
      );

      expect(result).toMatch(/^Results 0-9 of 150/);
    });

    it("handles offset beyond total", async () => {
      const result = await glob.execute(
        { pattern: "*.txt", offset: 200 },
        deps
      );

      expect(result).toContain("offset beyond end");
    });
  });

  describe("output size guarantees", () => {
    it("read never exceeds 10k", async () => {
      const content = Array.from({ length: 10000 }, (_, i) => `line ${i + 1}`).join("\n");
      await write.execute({ file_path: "huge.txt", content }, deps);

      const result = await read.execute({ file_path: "huge.txt" }, deps);

      expect(result.length).toBeLessThan(10000);
    });

    it("bash never exceeds specified limit", async () => {
      const result = await bash.execute(
        { command: `node -e "console.log('x'.repeat(20000))"`, max_output_chars: 5000 },
        deps
      );

      expect(result.length).toBeLessThan(5500); // with metadata
    });

    it("glob never exceeds 10k", async () => {
      // Create files with very long names
      for (let i = 0; i < 200; i++) {
        await write.execute(
          { file_path: `${"x".repeat(100)}${i}.txt`, content: "test" },
          deps
        );
      }

      const result = await glob.execute({ pattern: "*.txt" }, deps);

      expect(result.length).toBeLessThan(10000);
    });
  });
});
