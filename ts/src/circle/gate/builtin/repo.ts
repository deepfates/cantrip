import { promises as fs } from "fs";
import type { Dirent } from "fs";
import path from "path";
import { exec as execCallback } from "child_process";
import { promisify } from "util";

import type { BoundGate, GateDocs } from "../gate";
import { Depends } from "../depends";
import { rawGate } from "../raw";

const execAsync = promisify(execCallback);

const MAX_FILE_RESULTS = 500;
const DEFAULT_GLOB = "**/*";
const DEFAULT_READ_LINES = 200;
const MAX_READ_LINES = 1_000;
const MAX_READ_CHARS = 10_000;
const MAX_DIFF_CHARS = 15_000;
const DEFAULT_LOG_COUNT = 20;
const MAX_LOG_COUNT = 100;
const GIT_MAX_BUFFER = 4 * 1024 * 1024;

const EXCLUDED_DIRS = new Set(["node_modules", ".git"]);
const BINARY_EXTENSIONS = new Set(
  [
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".bmp",
    ".ico",
    ".svg",
    ".pdf",
    ".exe",
    ".dll",
    ".so",
    ".dylib",
    ".zip",
    ".tar",
    ".gz",
    ".tgz",
    ".bz2",
    ".xz",
    ".7z",
    ".rar",
    ".mp3",
    ".wav",
    ".flac",
    ".mp4",
    ".mov",
    ".avi",
    ".webm",
    ".webp",
    ".ttf",
    ".otf",
    ".woff",
    ".woff2",
    ".bin",
    ".class",
    ".jar",
  ].map((ext) => ext.toLowerCase()),
);

class RepoSecurityError extends Error {}

export class RepoContext {
  readonly root_dir: string;

  constructor(root_dir: string) {
    this.root_dir = path.resolve(root_dir);
  }

  resolvePath(targetPath: string): string {
    if (!targetPath) {
      throw new RepoSecurityError("Path is required");
    }
    const resolved = path.isAbsolute(targetPath)
      ? path.resolve(targetPath)
      : path.resolve(this.root_dir, targetPath);
    const relative = path.relative(this.root_dir, resolved);
    if (relative.startsWith("..") || path.isAbsolute(relative)) {
      throw new RepoSecurityError(`Path escapes repo: ${targetPath}`);
    }
    return resolved;
  }

  relativeFromAbsolute(absPath: string): string {
    const relative = path.relative(this.root_dir, absPath);
    if (relative.startsWith("..") || path.isAbsolute(relative)) {
      throw new RepoSecurityError(`Path escapes repo: ${absPath}`);
    }
    return normalizeRelativePath(relative);
  }
}

export function getRepoContext(): RepoContext {
  throw new Error("Override via dependency_overrides");
}

const repoContextDepends = new Depends(getRepoContext);

type RepoFilesArgs = {
  glob_pattern?: string;
};

const repoFilesDocs: GateDocs = {
  sandbox_name: "repo_files",
  signature: "repo_files(glob_pattern?: string): string[]",
  description:
    "List files in the repository that match a glob pattern (defaults to **/*). Paths are relative to the repo root, excluding node_modules, .git, and common binary files. Limited to 500 matches.",
  section: "REPO",
};

const repoFilesGate = rawGate<RepoFilesArgs>(
  {
    name: "repo_files",
    description: "Return relative file paths in the repository that match a glob pattern.",
    parameters: {
      type: "object",
      properties: {
        glob_pattern: {
          type: "string",
          description: "Glob pattern such as src/**/*.ts (defaults to **/*).",
        },
      },
      required: [],
      additionalProperties: false,
    },
  },
  async ({ glob_pattern }, deps) => {
    const ctx = deps.repo as RepoContext;
    const pattern = (glob_pattern ?? "").trim() || DEFAULT_GLOB;

    try {
      const matcher = globToRegExp(pattern);
      const files = await collectFiles(ctx, matcher);
      return files;
    } catch (err: any) {
      return `Error listing repo files: ${String(err?.message ?? err)}`;
    }
  },
  { dependencies: { repo: repoContextDepends } },
);
repoFilesGate.docs = repoFilesDocs;

type RepoReadArgs = {
  path: string;
  options?: {
    offset?: number;
    limit?: number;
  };
};

const repoReadDocs: GateDocs = {
  sandbox_name: "repo_read",
  signature: "repo_read(path: string, options?: { offset?: number; limit?: number }): string",
  description:
    "Read text from a file inside the repo with optional offset and limit (default 200 lines). Output is capped at 10k characters with a [truncated] marker.",
  section: "REPO",
};

const repoReadGate = rawGate<RepoReadArgs>(
  {
    name: "repo_read",
    description: "Read a slice of a repo file with optional line offset and limit.",
    parameters: {
      type: "object",
      properties: {
        path: { type: "string", description: "Path relative to the repo root" },
        options: {
          type: "object",
          properties: {
            offset: { type: "integer", minimum: 0 },
            limit: { type: "integer", minimum: 1 },
          },
          additionalProperties: false,
        },
      },
      required: ["path"],
      additionalProperties: false,
    },
  },
  async ({ path: filePath, options }, deps) => {
    const ctx = deps.repo as RepoContext;
    const offset = Math.max(0, options?.offset ?? 0);
    const limit = Math.max(1, Math.min(options?.limit ?? DEFAULT_READ_LINES, MAX_READ_LINES));

    try {
      const resolved = ctx.resolvePath(filePath);
      const stats = await fs.stat(resolved);
      if (!stats.isFile()) {
        return "Error: Path is not a regular file";
      }
      const buffer = await fs.readFile(resolved);
      if (buffer.includes(0)) {
        return "Error: Binary file detected";
      }

      const content = buffer.toString("utf8");
      const lines = content.split(/\r?\n/);
      const slice = lines.slice(offset, offset + limit);
      let output = slice.join("\n");
      if (output.length > MAX_READ_CHARS) {
        output = output.slice(0, MAX_READ_CHARS) + "\n[truncated]";
      }
      return output;
    } catch (err: any) {
      return `Error reading repo file: ${String(err?.message ?? err)}`;
    }
  },
  { dependencies: { repo: repoContextDepends } },
);
repoReadGate.docs = repoReadDocs;

type RepoGitLogArgs = { n?: number };

const repoGitLogDocs: GateDocs = {
  sandbox_name: "repo_git_log",
  signature: "repo_git_log(n?: number): string",
  description:
    "Show recent git commits from the repo with hash, author, date, and message per line (default 20, max 100).",
  section: "REPO",
};

const repoGitLogGate = rawGate<RepoGitLogArgs>(
  {
    name: "repo_git_log",
    description: "Show recent git commits for the repository.",
    parameters: {
      type: "object",
      properties: {
        n: { type: "integer", minimum: 1, description: "Number of commits to show (default 20, max 100)" },
      },
      required: [],
      additionalProperties: false,
    },
  },
  async ({ n }, deps) => {
    const ctx = deps.repo as RepoContext;
    const count = Math.min(Math.max(1, n ?? DEFAULT_LOG_COUNT), MAX_LOG_COUNT);
    const format = "%h%x09%an%x09%ad%x09%s";
    const command = `git log -n ${count} --date=iso-strict --pretty=format:${format}`;

    try {
      const { stdout } = await execAsync(command, { cwd: ctx.root_dir, maxBuffer: GIT_MAX_BUFFER });
      const trimmed = stdout.trim();
      if (!trimmed) {
        return "No commits found";
      }
      return trimmed
        .split("\n")
        .map((line) => {
          const [hash, author, date, ...messageParts] = line.split("\t");
          const message = messageParts.join("\t");
          return `${hash} | ${author} | ${date} | ${message}`;
        })
        .join("\n");
    } catch (err: any) {
      return `Error running git log: ${String(err?.message ?? err)}`;
    }
  },
  { dependencies: { repo: repoContextDepends } },
);
repoGitLogGate.docs = repoGitLogDocs;

const repoGitStatusDocs: GateDocs = {
  sandbox_name: "repo_git_status",
  signature: "repo_git_status(): string",
  description: "Show `git status --porcelain` for the repo root.",
  section: "REPO",
};

const repoGitStatusGate = rawGate<Record<string, never>>(
  {
    name: "repo_git_status",
    description: "Display the working tree status via git status --porcelain.",
    parameters: {
      type: "object",
      properties: {},
      required: [],
      additionalProperties: false,
    },
  },
  async (_args, deps) => {
    const ctx = deps.repo as RepoContext;
    try {
      const { stdout } = await execAsync("git status --porcelain", {
        cwd: ctx.root_dir,
        maxBuffer: GIT_MAX_BUFFER,
      });
      const cleaned = stdout.trimEnd();
      return cleaned || "Clean working tree";
    } catch (err: any) {
      return `Error running git status: ${String(err?.message ?? err)}`;
    }
  },
  { dependencies: { repo: repoContextDepends } },
);
repoGitStatusGate.docs = repoGitStatusDocs;

type RepoGitDiffArgs = { path?: string };

const repoGitDiffDocs: GateDocs = {
  sandbox_name: "repo_git_diff",
  signature: "repo_git_diff(path?: string): string",
  description: "Show unstaged git diff output for the repo or a specific path (truncated at 15k characters).",
  section: "REPO",
};

const repoGitDiffGate = rawGate<RepoGitDiffArgs>(
  {
    name: "repo_git_diff",
    description: "Display unstaged git diff output, optionally filtering to a path.",
    parameters: {
      type: "object",
      properties: {
        path: { type: "string", description: "Optional path relative to the repo root to diff" },
      },
      required: [],
      additionalProperties: false,
    },
  },
  async ({ path: target }, deps) => {
    const ctx = deps.repo as RepoContext;
    try {
      let command = "git diff --no-color";
      if (target) {
        const resolved = ctx.resolvePath(target);
        const relative = ctx.relativeFromAbsolute(resolved);
        command += ` -- ${shellEscape(relative)}`;
      }

      const { stdout } = await execAsync(command, { cwd: ctx.root_dir, maxBuffer: GIT_MAX_BUFFER });
      const cleaned = stdout.trimEnd();
      if (!cleaned) {
        return "No diff";
      }
      if (cleaned.length > MAX_DIFF_CHARS) {
        return cleaned.slice(0, MAX_DIFF_CHARS) + "\n[truncated]";
      }
      return cleaned;
    } catch (err: any) {
      return `Error running git diff: ${String(err?.message ?? err)}`;
    }
  },
  { dependencies: { repo: repoContextDepends } },
);
repoGitDiffGate.docs = repoGitDiffDocs;

export const repoGates: BoundGate[] = [
  repoFilesGate,
  repoReadGate,
  repoGitLogGate,
  repoGitStatusGate,
  repoGitDiffGate,
];

export { repoContextDepends as getRepoContextDepends };

async function collectFiles(ctx: RepoContext, matcher: RegExp): Promise<string[]> {
  const results: string[] = [];

  async function walk(current: string): Promise<void> {
    if (results.length >= MAX_FILE_RESULTS) return;
    let entries: Dirent[];
    try {
      entries = await fs.readdir(current, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (results.length >= MAX_FILE_RESULTS) return;
      if (entry.isSymbolicLink()) continue;
      const absolute = path.join(current, entry.name);
      if (entry.isDirectory()) {
        if (EXCLUDED_DIRS.has(entry.name)) continue;
        await walk(absolute);
      } else if (entry.isFile()) {
        if (isBinaryExtension(entry.name)) continue;
        const relative = ctx.relativeFromAbsolute(absolute);
        if (matcher.test(relative)) {
          results.push(relative);
        }
      }
    }
  }

  await walk(ctx.root_dir);
  return results.sort();
}

function globToRegExp(pattern: string): RegExp {
  const normalized = normalizeGlob(pattern);
  let regex = "^";
  let i = 0;

  while (i < normalized.length) {
    const char = normalized[i];
    if (char === "*") {
      if (normalized[i + 1] === "*") {
        if (normalized[i + 2] === "/") {
          regex += "(?:.*\\/)?";
          i += 3;
          continue;
        }
        regex += ".*";
        i += 2;
        continue;
      }
      regex += "[^/]*";
      i += 1;
      continue;
    }
    if (char === "?") {
      regex += "[^/]";
      i += 1;
      continue;
    }
    if (char === "/") {
      regex += "\\/";
      i += 1;
      continue;
    }
    if (/[.+^${}()|[\]\\]/.test(char)) {
      regex += `\\${char}`;
    } else {
      regex += char;
    }
    i += 1;
  }

  regex += "$";
  return new RegExp(regex);
}

function normalizeGlob(pattern: string): string {
  const normalized = (pattern || DEFAULT_GLOB).replace(/\\/g, "/").replace(/^\.\//, "");
  if (normalized.startsWith("/")) {
    return normalized.slice(1);
  }
  return normalized || DEFAULT_GLOB;
}

function normalizeRelativePath(p: string): string {
  const normalized = p.split(path.sep).join("/");
  if (!normalized || normalized === ".") {
    return ".";
  }
  return normalized.replace(/^\.\//, "");
}

function isBinaryExtension(filename: string): boolean {
  const ext = path.extname(filename).toLowerCase();
  return !!ext && BINARY_EXTENSIONS.has(ext);
}

function shellEscape(arg: string): string {
  if (arg === "") return "''";
  return `'${arg.replace(/'/g, `'\\''`)}'`;
}
