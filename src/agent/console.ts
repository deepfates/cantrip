import {
  FinalResponseEvent,
  TextEvent,
  ToolCallEvent,
  ToolResultEvent,
  type AgentEvent,
} from "./events";

export type ConsoleRendererState = {
  sawText: boolean;
  sawTaskComplete: boolean;
};

export type ConsoleRendererOptions = {
  verbose?: boolean;
  stdout?: NodeJS.WritableStream;
  stderr?: NodeJS.WritableStream;
};

export type ConsoleRenderer = {
  createState: () => ConsoleRendererState;
  handle: (event: AgentEvent, state: ConsoleRendererState) => void;
};

const trimTrailingWhitespace = (value: string): string =>
  value.replace(/\s+$/, "");

const writeLine = (stream: NodeJS.WritableStream, line: string): void => {
  stream.write(`${line}\n`);
};

/**
 * Truncate a string for display, showing beginning and end if too long.
 */
const truncateForDisplay = (s: string, maxLen: number): string => {
  if (s.length <= maxLen) return s;
  const half = Math.floor((maxLen - 5) / 2);
  return s.slice(0, half) + "[...]" + s.slice(-half);
};

/**
 * Format tool arguments for display.
 * For 'js' tool, show truncated code preview.
 */
const formatToolArgs = (tool: string, args: Record<string, any>): string => {
  if (tool === "js" && args.code) {
    // Show first line or truncated preview
    const code = args.code as string;
    const firstLine = code.split("\n").find((l) => l.trim()) ?? code;
    const preview = truncateForDisplay(firstLine.trim(), 60);
    return `code: "${preview}"`;
  }
  const json = JSON.stringify(args);
  return truncateForDisplay(json, 80);
};

export const createConsoleRenderer = (
  options: ConsoleRendererOptions = {},
): ConsoleRenderer => {
  const verbose = options.verbose ?? false;
  const stdout = options.stdout ?? process.stdout;
  const stderr = options.stderr ?? process.stderr;

  return {
    createState: () => ({ sawText: false, sawTaskComplete: false }),
    handle: (event, state) => {
      if (event instanceof ToolCallEvent) {
        if (verbose) {
          const argsStr = formatToolArgs(event.tool, event.args);
          writeLine(stderr, `» ${event.tool}(${argsStr})`);
        } else {
          writeLine(stderr, `» ${event.tool}`);
        }
        return;
      }
      if (event instanceof ToolResultEvent) {
        if (verbose) {
          const line = event.result?.toString?.() ?? String(event.result);
          // Check if this is a TaskComplete result
          if (line.startsWith("Task completed:")) {
            state.sawTaskComplete = true;
            // Show abbreviated version in verbose - full output comes in FinalResponse
            writeLine(stderr, `│ Task completed`);
          } else {
            // Truncate long results
            writeLine(stderr, `│ ${truncateForDisplay(line, 200)}`);
          }
        }
        return;
      }
      if (event instanceof TextEvent) {
        const text = trimTrailingWhitespace(event.content);
        if (text) writeLine(stdout, text);
        state.sawText = true;
        return;
      }
      if (event instanceof FinalResponseEvent) {
        // Always show final response (it's the actual answer)
        // The sawText check prevents double-printing when assistant responds without tools
        if (!state.sawText) {
          const text = trimTrailingWhitespace(event.content);
          if (text) writeLine(stdout, text);
        }
      }
    },
  };
};
