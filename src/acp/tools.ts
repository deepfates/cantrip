import type { ToolKind, ToolCallLocation } from "@agentclientprotocol/sdk";

const TOOL_KINDS: Record<string, ToolKind> = {
  read: "read",
  write: "edit",
  edit: "edit",
  bash: "execute",
  glob: "search",
  browser: "fetch",
  browser_interactive: "fetch",
  browser_readonly: "fetch",
  js: "execute",
  js_run: "execute",
  done: "other",
};

export function getToolKind(toolName: string): ToolKind {
  return TOOL_KINDS[toolName] ?? "other";
}

export function getToolLocations(
  toolName: string,
  args: Record<string, any>,
): ToolCallLocation[] {
  const path = args.file_path ?? args.path;
  if (path && typeof path === "string") {
    return [{ path }];
  }
  return [];
}

export function getToolTitle(
  toolName: string,
  args: Record<string, any>,
): string {
  switch (toolName) {
    case "read":
      return `Reading ${args.file_path ?? "file"}`;
    case "write":
      return `Writing ${args.file_path ?? "file"}`;
    case "edit":
      return `Editing ${args.file_path ?? "file"}`;
    case "bash": {
      const cmd = args.command;
      if (typeof cmd === "string" && cmd.length > 0) {
        return `$ ${cmd}`;
      }
      return `Running command`;
    }
    case "glob":
      return `Searching files`;
    case "browser":
    case "browser_interactive":
    case "browser_readonly":
      return `Browsing`;
    case "js":
    case "js_run": {
      const code = args.code;
      if (typeof code === "string" && code.length > 0) {
        const firstLine = code
          .split("\n")
          .map((l: string) => l.trim())
          .find((l: string) => l.length > 0);
        if (firstLine) {
          return `Running: ${firstLine}`;
        }
      }
      return `Running JavaScript`;
    }
    case "done":
      return `Completing task`;
    default:
      return toolName;
  }
}
