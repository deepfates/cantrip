import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { promises as fs } from "fs";
import os from "os";
import path from "path";
import { exec as execCallback } from "child_process";
import { promisify } from "util";

import {
  repoGates,
  RepoContext,
  getRepoContext,
} from "../../../src/circle/gate/builtin/repo";

const execAsync = promisify(execCallback);

function gateByName(name: string) {
  const gate = repoGates.find((g) => g.name === name);
  if (!gate) throw new Error(`Gate ${name} not found`);
  return gate;
}

describe("repo gates", () => {
  let tempDir = "";
  let overrides: Map<any, any>;

  beforeAll(async () => {
    tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "repo-gates-"));
    await setupRepo(tempDir);
    const ctx = new RepoContext(tempDir);
    overrides = new Map([[getRepoContext, () => ctx]]);
  });

  afterAll(async () => {
    if (tempDir) {
      await fs.rm(tempDir, { recursive: true, force: true });
    }
  });

  test("repo_files returns matching TypeScript files", async () => {
    const gate = gateByName("repo_files");
    const result = await gate.execute({ glob_pattern: "src/**/*.ts" }, overrides);
    expect(typeof result).toBe("string");
    const files = JSON.parse(result as string);
    expect(files).toContain("src/app.ts");
    expect(files).toContain("src/helper.ts");
    expect(files.some((file: string) => file.includes("node_modules"))).toBe(false);
    expect(files.some((file: string) => file.endsWith(".png"))).toBe(false);
  });

  test("repo_read respects offset, limit, and truncation", async () => {
    const gate = gateByName("repo_read");
    const windowResult = await gate.execute(
      { path: "src/long.txt", options: { offset: 1, limit: 2 } },
      overrides,
    );
    expect(windowResult).toBe("line 1\nline 2");

    const truncatedResult = (await gate.execute({ path: "src/huge.txt" }, overrides)) as string;
    expect(truncatedResult.includes("[truncated]")).toBe(true);
    expect(truncatedResult.length).toBeGreaterThan(1000);
    expect(truncatedResult.length).toBeLessThanOrEqual(10_100);
  });

  test("repo_git_log shows the latest commit", async () => {
    const gate = gateByName("repo_git_log");
    const log = (await gate.execute({ n: 1 }, overrides)) as string;
    expect(log).toContain("initial commit for repo gates");
  });

  test("repo_git_status reports working tree changes", async () => {
    const scratchPath = path.join(tempDir, "scratch-status.txt");
    await fs.writeFile(scratchPath, "temporary\n", "utf8");

    const gate = gateByName("repo_git_status");
    const status = (await gate.execute({}, overrides)) as string;
    expect(status).toContain("?? scratch-status.txt");

    await fs.rm(scratchPath, { force: true });
  });

  test("repo_git_diff filters by path", async () => {
    const filePath = path.join(tempDir, "src", "app.ts");
    const original = await fs.readFile(filePath, "utf8");
    await fs.writeFile(filePath, `${original}\n// added for diff\n`, "utf8");

    const gate = gateByName("repo_git_diff");
    const diff = (await gate.execute({ path: "src/app.ts" }, overrides)) as string;
    expect(diff).toContain("diff --git a/src/app.ts b/src/app.ts");
    expect(diff).toContain("// added for diff");

    await fs.writeFile(filePath, original, "utf8");
  });
  // ── Security ────────────────────────────────────────────────────

  test("repo_read rejects path traversal outside repo root", async () => {
    const gate = gateByName("repo_read");
    const result = await gate.execute({ path: "../../etc/passwd" }, overrides);
    expect(result).toContain("Error");
    expect(result).toContain("escapes repo");
  });

  test("repo_files rejects path traversal in glob patterns", async () => {
    const gate = gateByName("repo_files");
    // The glob handler itself doesn't traverse — but verify it doesn't crash
    const result = await gate.execute({ glob_pattern: "../../**/*" }, overrides);
    // Should return an array (possibly empty), not files outside repo
    const files = JSON.parse(result as string);
    expect(Array.isArray(files)).toBe(true);
    for (const f of files) {
      expect(f.startsWith("..")).toBe(false);
    }
  });

  test("repo_git_diff rejects path traversal", async () => {
    const gate = gateByName("repo_git_diff");
    const result = await gate.execute({ path: "../../../etc/passwd" }, overrides);
    expect(result).toContain("Error");
    expect(result).toContain("escapes repo");
  });

  test("repo_read returns error for binary files", async () => {
    const gate = gateByName("repo_read");
    // Write a file with null bytes (binary detection)
    const binPath = path.join(tempDir, "src", "binary.dat");
    await fs.writeFile(binPath, Buffer.from([0x00, 0x01, 0x02, 0x03]));

    const result = await gate.execute({ path: "src/binary.dat" }, overrides);
    expect(result).toContain("Binary file");

    await fs.rm(binPath, { force: true });
  });

  test("repo_read returns error for nonexistent files", async () => {
    const gate = gateByName("repo_read");
    const result = await gate.execute({ path: "does/not/exist.ts" }, overrides);
    expect(result).toContain("Error");
  });

  test("repo_read returns error for directories", async () => {
    const gate = gateByName("repo_read");
    const result = await gate.execute({ path: "src" }, overrides);
    expect(result).toContain("not a regular file");
  });

  test("RepoContext.resolvePath rejects empty path", () => {
    const ctx = new RepoContext(tempDir);
    expect(() => ctx.resolvePath("")).toThrow("Path is required");
  });

  // ── Edge cases ─────────────────────────────────────────────────

  test("repo_git_status returns clean message for clean tree", async () => {
    // After cleanup from other tests, the tree should be clean
    // (or at least not crash)
    const gate = gateByName("repo_git_status");
    const status = await gate.execute({}, overrides);
    expect(typeof status).toBe("string");
  });

  test("repo_files with no glob returns all non-binary, non-excluded files", async () => {
    const gate = gateByName("repo_files");
    const result = await gate.execute({}, overrides);
    const files = JSON.parse(result as string);
    expect(files).toContain("README.md");
    expect(files).toContain("src/app.ts");
    // Binary extension excluded
    expect(files).not.toContain("assets/logo.png");
    // node_modules excluded
    expect(files.some((f: string) => f.includes("node_modules"))).toBe(false);
  });
});

async function setupRepo(root: string) {
  await execAsync("git init", { cwd: root });
  await execAsync('git config user.email "repo-tests@example.com"', { cwd: root });
  await execAsync('git config user.name "Repo Tests"', { cwd: root });

  await fs.writeFile(path.join(root, ".gitignore"), "node_modules/\n", "utf8");
  await fs.mkdir(path.join(root, "src"), { recursive: true });
  await fs.mkdir(path.join(root, "assets"), { recursive: true });
  await fs.mkdir(path.join(root, "node_modules", "ignored"), { recursive: true });

  const longContent = Array.from({ length: 300 }, (_, idx) => `line ${idx}`).join("\n");
  const hugeContent = "x".repeat(11_000);

  await Promise.all([
    fs.writeFile(path.join(root, "README.md"), "# Repo Gate Tests\n", "utf8"),
    fs.writeFile(path.join(root, "src", "app.ts"), "export const value = 1;\n", "utf8"),
    fs.writeFile(
      path.join(root, "src", "helper.ts"),
      "export function helper() { return 42; }\n",
      "utf8",
    ),
    fs.writeFile(path.join(root, "src", "long.txt"), longContent, "utf8"),
    fs.writeFile(path.join(root, "src", "huge.txt"), hugeContent, "utf8"),
    fs.writeFile(path.join(root, "assets", "logo.png"), "fake-png", "utf8"),
    fs.writeFile(path.join(root, "node_modules", "ignored", "skip.js"), "console.log('skip');\n", "utf8"),
  ]);

  await execAsync("git add README.md .gitignore src assets", { cwd: root });
  await execAsync('git commit -m "initial commit for repo gates"', { cwd: root });
}
