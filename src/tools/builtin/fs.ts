import { promises as fs } from "fs";
import path from "path";
import { exec } from "child_process";
import { promisify } from "util";

import { Depends } from "../../tools/depends";
import { tool } from "../../tools/decorator";

const execAsync = promisify(exec);

// Loria node size constraints
const SAFE_OUTPUT_LIMIT = 9_500;

class SecurityError extends Error {}

export class SandboxContext {
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

export function getSandboxContext(): SandboxContext {
  throw new Error("Override via dependency_overrides");
}

/**
 * Shared Depends instance for getSandboxContext.
 * Use this as a key in dependency_overrides Map.
 */
const sandboxContextDepends = new Depends(getSandboxContext);

export const bash = tool(
  "Execute a shell command and return output. Output is automatically limited to max_output_chars (default 9000 chars). Use shell pipes and filters to process large outputs.",
  async (
    {
      command,
      timeout,
      max_output_chars,
    }: {
      command: string;
      timeout?: number;
      max_output_chars?: number;
    },
    deps,
  ) => {
    const ctx = deps.ctx as SandboxContext;
    const maxChars = max_output_chars ?? 9000;

    // Validate command length
    if (command.length > 5000) {
      return `Error: Command too long (${command.length} chars). Maximum 5000.`;
    }

    try {
      const { stdout, stderr } = await execAsync(command, {
        cwd: ctx.working_dir,
        timeout: timeout ?? 30_000,
      });
      let output = `${stdout}${stderr}`.trim();

      if (!output) return "(no output)";

      // Truncate if needed
      if (output.length > maxChars) {
        // Try to truncate at last newline
        const lastNewline = output.lastIndexOf("\n", maxChars);
        if (lastNewline > maxChars / 2) {
          output = output.substring(0, lastNewline);
        } else {
          output = output.substring(0, maxChars);
        }
        output += `\n\n... [output truncated at ${maxChars} chars]`;
      }

      return output;
    } catch (err: any) {
      return `Error: ${String(err?.message ?? err)}`;
    }
  },
  {
    name: "bash",
    schema: {
      type: "object",
      properties: {
        command: { type: "string", maxLength: 5000 },
        timeout: { type: "integer" },
        max_output_chars: { type: "integer" },
      },
      required: ["command"],
      additionalProperties: false,
    },
    dependencies: { ctx: sandboxContextDepends },
  },
);

export const read = tool(
  "Read contents of a file with line numbers. Returns a window of lines starting from start_line for up to max_lines. Shows line range and total count for navigation.",
  async (
    {
      file_path,
      start_line,
      max_lines,
    }: {
      file_path: string;
      start_line?: number;
      max_lines?: number;
    },
    deps,
  ) => {
    const ctx = deps.ctx as SandboxContext;
    const startLine = start_line ?? 1;
    const maxLines = max_lines ?? 300;

    try {
      const resolved = ctx.resolvePath(file_path);

      // Check if binary
      const buffer = await fs.readFile(resolved);
      if (buffer.includes(0)) {
        return `Error: Binary file detected (${buffer.length} bytes)`;
      }

      const content = buffer.toString("utf8");
      const allLines = content.split(/\r?\n/);
      const totalLines = allLines.length;

      // Handle start_line beyond EOF
      if (startLine > totalLines) {
        return `Lines ${startLine}-${startLine} of ${totalLines} (empty - file has ${totalLines} lines)`;
      }

      // Slice the window
      const endLine = Math.min(startLine + maxLines - 1, totalLines);
      const windowLines = allLines.slice(startLine - 1, endLine);

      // Build output with line numbers
      let output = `Lines ${startLine}-${endLine} of ${totalLines}\n\n`;

      for (let i = 0; i < windowLines.length; i++) {
        const lineNum = startLine + i;
        let line = windowLines[i];

        // Truncate individual lines if too long
        if (line.length > 500) {
          line =
            line.substring(0, 500) +
            `... [line truncated - ${line.length} chars total]`;
        }

        const lineStr = `${String(lineNum).padStart(4)}  ${line}\n`;

        // Check if we're approaching the limit
        if (output.length + lineStr.length > SAFE_OUTPUT_LIMIT) {
          output += `\n(output limited - showing ${i} of ${windowLines.length} lines)`;
          break;
        }

        output += lineStr;
      }

      return output.trimEnd();
    } catch (err: any) {
      return `Error reading file: ${String(err?.message ?? err)}`;
    }
  },
  {
    name: "read",
    schema: {
      type: "object",
      properties: {
        file_path: { type: "string" },
        start_line: { type: "integer", minimum: 1 },
        max_lines: { type: "integer", minimum: 1 },
      },
      required: ["file_path"],
      additionalProperties: false,
    },
    dependencies: { ctx: sandboxContextDepends },
  },
);

export const write = tool(
  "Write content to a file. Content limited to 50,000 characters. For larger data, write in multiple chunks or separate files.",
  async (
    { file_path, content }: { file_path: string; content: string },
    deps,
  ) => {
    const ctx = deps.ctx as SandboxContext;

    // Validate content length
    if (content.length > 50_000) {
      return `Error: Content too large (${content.length} chars). Maximum 50,000.`;
    }

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
        content: { type: "string", maxLength: 50_000 },
      },
      required: ["file_path", "content"],
      additionalProperties: false,
    },
    dependencies: { ctx: sandboxContextDepends },
  },
);

export const edit = tool(
  "Replace all occurrences of old_string with new_string in a file. Both strings limited to 10,000 characters each. Returns summary only.",
  async (
    {
      file_path,
      old_string,
      new_string,
    }: { file_path: string; old_string: string; new_string: string },
    deps,
  ) => {
    const ctx = deps.ctx as SandboxContext;

    // Validate string lengths
    if (old_string.length > 10_000) {
      return `Error: Search string too large (${old_string.length} chars). Maximum 10,000.`;
    }
    if (new_string.length > 10_000) {
      return `Error: Replacement string too large (${new_string.length} chars). Maximum 10,000.`;
    }

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
        old_string: { type: "string", maxLength: 10_000 },
        new_string: { type: "string", maxLength: 10_000 },
      },
      required: ["file_path", "old_string", "new_string"],
      additionalProperties: false,
    },
    dependencies: { ctx: sandboxContextDepends },
  },
);

export const glob = tool(
  "Find files matching a glob pattern. Returns paginated results starting at offset for up to max_results items. Shows total count for navigation.",
  async (
    {
      pattern,
      cwd,
      offset,
      max_results,
    }: {
      pattern: string;
      cwd?: string;
      offset?: number;
      max_results?: number;
    },
    deps,
  ) => {
    const ctx = deps.ctx as SandboxContext;
    const startOffset = offset ?? 0;
    const maxResults = max_results ?? 100;

    try {
      const root = ctx.resolvePath(cwd ?? ".");
      const entries = await fs.readdir(root, { withFileTypes: true });
      const allResults: string[] = [];

      for (const entry of entries) {
        if (entry.isFile()) {
          const filename = entry.name;
          if (filename.match(new RegExp(pattern.replace(/\*/g, ".*")))) {
            allResults.push(path.join(root, filename));
          }
        }
      }

      const totalCount = allResults.length;

      if (totalCount === 0) {
        return "No matches";
      }

      // Handle offset beyond total
      if (startOffset >= totalCount) {
        return `Results ${startOffset}-${startOffset} of ${totalCount} (empty - offset beyond end)`;
      }

      // Slice the window
      const endOffset = Math.min(startOffset + maxResults, totalCount);
      const windowResults = allResults.slice(startOffset, endOffset);

      // Build output, checking size
      let output = `Results ${startOffset}-${endOffset - 1} of ${totalCount}\n\n`;
      let shownCount = 0;

      for (const result of windowResults) {
        const line = result + "\n";
        if (output.length + line.length > SAFE_OUTPUT_LIMIT) {
          output += `\n(limited by output size - showing ${shownCount} of ${windowResults.length} results)`;
          break;
        }
        output += line;
        shownCount++;
      }

      return output.trimEnd();
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
        offset: { type: "integer", minimum: 0 },
        max_results: { type: "integer", minimum: 1 },
      },
      required: ["pattern"],
      additionalProperties: false,
    },
    dependencies: { ctx: sandboxContextDepends },
  },
);

export { sandboxContextDepends as getSandboxContextDepends };

export const unsafeFsTools = [bash, read, write, edit, glob];
export const safeFsTools = [read, write, edit, glob];

/**
 * Tools for interacting with the filesystem, with dangerous tools removed.
 * @deprecated Use safeFsTools instead
 */
export const fsTools = safeFsTools;
