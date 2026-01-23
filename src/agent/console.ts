import {
  FinalResponseEvent,
  TextEvent,
  ToolCallEvent,
  ToolResultEvent,
  type AgentEvent,
} from "./events";

export type ConsoleRendererState = { sawText: boolean };

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

export const createConsoleRenderer = (
  options: ConsoleRendererOptions = {},
): ConsoleRenderer => {
  const verbose = options.verbose ?? false;
  const stdout = options.stdout ?? process.stdout;
  const stderr = options.stderr ?? process.stderr;

  return {
    createState: () => ({ sawText: false }),
    handle: (event, state) => {
      if (event instanceof ToolCallEvent) {
        if (verbose) writeLine(stderr, `» ${event.tool}`);
        return;
      }
      if (event instanceof ToolResultEvent) {
        if (verbose) {
          const line = event.result?.toString?.() ?? String(event.result);
          writeLine(stderr, `│ ${line}`);
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
        if (!state.sawText) {
          const text = trimTrailingWhitespace(event.content);
          if (text) writeLine(stdout, text);
        }
      }
    },
  };
};
