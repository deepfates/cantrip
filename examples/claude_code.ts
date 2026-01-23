import { promises as fs } from "fs";
import path from "path";
import { exec } from "child_process";
import { promisify } from "util";

import { Agent, TaskComplete } from "../src/agent/service";
import { ChatOpenAI } from "../src/llm/openai/chat";
import { Depends } from "../src/tools/depends";
import { tool } from "../src/tools/decorator";

const execAsync = promisify(exec);

class SecurityError extends Error {}

class SandboxContext {
  root_dir: string;
  working_dir: string;

  constructor(root_dir: string, working_dir: string) {
    this.root_dir = root_dir;
    this.working_dir = working_dir;
  }

  static async create(root_dir?: string): Promise<SandboxContext> {
    const root = root_dir ?? path.join(process.cwd(), "tmp", "sandbox");
    await fs.mkdir(root, { recursive: true });
    const resolved = path.resolve(root);
    return new SandboxContext(resolved, resolved);
  }

  resolvePath(p: string): string {
    const resolved = path.isAbsolute(p)
      ? path.resolve(p)
      : path.resolve(this.working_dir, p);
    if (!resolved.startsWith(this.root_dir)) {
      throw new SecurityError(`Path escapes sandbox: ${p} -> ${resolved}`);
    }
    return resolved;
  }
}

function getSandboxContext(): SandboxContext {
  throw new Error("Override via dependency_overrides");
}

const bash = tool(
  "Execute a shell command and return output",
  async ({ command, timeout }: { command: string; timeout?: number }, deps) => {
    const ctx = deps.ctx as SandboxContext;
    try {
      const { stdout, stderr } = await execAsync(command, {
        cwd: ctx.working_dir,
        timeout: timeout ?? 30_000,
      });
      const output = `${stdout}${stderr}`.trim();
      return output || "(no output)";
    } catch (err: any) {
      return `Error: ${String(err?.message ?? err)}`;
    }
  },
  {
    name: "bash",
    schema: {
      type: "object",
      properties: {
        command: { type: "string" },
        timeout: { type: "integer" },
      },
      required: ["command"],
      additionalProperties: false,
    },
    dependencies: { ctx: new Depends(getSandboxContext) },
  },
);

const read = tool(
  "Read contents of a file",
  async ({ file_path }: { file_path: string }, deps) => {
    const ctx = deps.ctx as SandboxContext;
    try {
      const resolved = ctx.resolvePath(file_path);
      const content = await fs.readFile(resolved, "utf8");
      const lines = content.split(/\r?\n/);
      return lines
        .map((line, i) => `${String(i + 1).padStart(4)}  ${line}`)
        .join("\n");
    } catch (err: any) {
      return `Error reading file: ${String(err?.message ?? err)}`;
    }
  },
  {
    name: "read",
    schema: {
      type: "object",
      properties: { file_path: { type: "string" } },
      required: ["file_path"],
      additionalProperties: false,
    },
    dependencies: { ctx: new Depends(getSandboxContext) },
  },
);

const write = tool(
  "Write content to a file",
  async (
    { file_path, content }: { file_path: string; content: string },
    deps,
  ) => {
    const ctx = deps.ctx as SandboxContext;
    try {
      const resolved = ctx.resolvePath(file_path);
      await fs.mkdir(path.dirname(resolved), { recursive: true });
      await fs.writeFile(resolved, content, "utf8");
      return `Wrote ${content.length} bytes to ${file_path}`;
    } catch (err: any) {
      return `Error writing file: ${String(err?.message ?? err)}`;
    }
  },
  {
    name: "write",
    schema: {
      type: "object",
      properties: {
        file_path: { type: "string" },
        content: { type: "string" },
      },
      required: ["file_path", "content"],
      additionalProperties: false,
    },
    dependencies: { ctx: new Depends(getSandboxContext) },
  },
);

const edit = tool(
  "Replace text in a file",
  async (
    {
      file_path,
      old_string,
      new_string,
    }: { file_path: string; old_string: string; new_string: string },
    deps,
  ) => {
    const ctx = deps.ctx as SandboxContext;
    try {
      const resolved = ctx.resolvePath(file_path);
      const content = await fs.readFile(resolved, "utf8");
      if (!content.includes(old_string))
        return `String not found in ${file_path}`;
      const count = content.split(old_string).length - 1;
      const updated = content.replaceAll(old_string, new_string);
      await fs.writeFile(resolved, updated, "utf8");
      return `Replaced ${count} occurrence(s) in ${file_path}`;
    } catch (err: any) {
      return `Error editing file: ${String(err?.message ?? err)}`;
    }
  },
  {
    name: "edit",
    schema: {
      type: "object",
      properties: {
        file_path: { type: "string" },
        old_string: { type: "string" },
        new_string: { type: "string" },
      },
      required: ["file_path", "old_string", "new_string"],
      additionalProperties: false,
    },
    dependencies: { ctx: new Depends(getSandboxContext) },
  },
);

const glob = tool(
  "Find files matching a glob pattern",
  async ({ pattern, cwd }: { pattern: string; cwd?: string }, deps) => {
    const ctx = deps.ctx as SandboxContext;
    try {
      const root = ctx.resolvePath(cwd ?? ".");
      const entries = await fs.readdir(root, { withFileTypes: true });
      const results: string[] = [];
      for (const entry of entries) {
        if (entry.isFile()) {
          const filename = entry.name;
          if (filename.match(new RegExp(pattern.replace(/\*/g, ".*")))) {
            results.push(path.join(root, filename));
          }
        }
      }
      return results.join("\n") || "No matches";
    } catch (err: any) {
      return `Error: ${String(err?.message ?? err)}`;
    }
  },
  {
    name: "glob",
    schema: {
      type: "object",
      properties: {
        pattern: { type: "string" },
        cwd: { type: "string" },
      },
      required: ["pattern"],
      additionalProperties: false,
    },
    dependencies: { ctx: new Depends(getSandboxContext) },
  },
);

const done = tool(
  "Signal task completion",
  async ({ message }: { message: string }) => {
    throw new TaskComplete(message);
  },
  {
    name: "done",
    schema: {
      type: "object",
      properties: { message: { type: "string" } },
      required: ["message"],
      additionalProperties: false,
    },
  },
);

export async function main() {
  const ctx = await SandboxContext.create();
  const agent = new Agent({
    llm: new ChatOpenAI({ model: "gpt-4o" }),
    tools: [bash, read, write, edit, glob, done],
    system_prompt: `Coding assistant. Working dir: ${ctx.working_dir}`,
    dependency_overrides: new Map([[getSandboxContext, () => ctx]]),
  });

  console.log("Agent ready. Ctrl+C to exit.");
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", async (chunk) => {
    const task = chunk.toString().trim();
    if (!task) return;
    for await (const event of agent.query_stream(task)) {
      if ((event as any).tool) {
        console.log(`  → ${(event as any).tool}`);
      } else if ((event as any).content) {
        console.log(`\n${(event as any).content}`);
      }
    }
  });
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
