/**
 * RLM-specialized console renderer with ANSI colors and structured output.
 *
 * Extends the base ConsoleRenderer to provide:
 * - Syntax-highlighted JS code blocks for 'js' tool calls
 * - Color-coded results with structured formatting
 * - Styled error messages
 * - Visual tree structure for sub-agent delegation (stderr)
 */

import {
  TextEvent,
  ToolCallEvent,
  ToolResultEvent,
  FinalResponseEvent,
  UsageEvent,
  type TurnEvent,
} from "../entity/events";

// ANSI color codes
const c = {
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  dim: "\x1b[2m",
  italic: "\x1b[3m",
  // Foreground
  red: "\x1b[31m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  magenta: "\x1b[35m",
  cyan: "\x1b[36m",
  white: "\x1b[37m",
  gray: "\x1b[90m",
  // Bright
  brightGreen: "\x1b[92m",
  brightYellow: "\x1b[93m",
  brightCyan: "\x1b[96m",
};

export type RlmConsoleRendererState = {
  sawText: boolean;
  turnCount: number;
};

export type RlmConsoleRendererOptions = {
  verbose?: boolean;
  /** Show code in tool calls (default: true) */
  showCode?: boolean;
  /** Max lines of code to display (default: 20) */
  maxCodeLines?: number;
  stdout?: NodeJS.WritableStream;
  stderr?: NodeJS.WritableStream;
};

export type RlmConsoleRenderer = {
  createState: () => RlmConsoleRendererState;
  handle: (event: TurnEvent, state: RlmConsoleRendererState) => void;
};

/**
 * Minimal JS syntax highlighting with ANSI codes.
 * Highlights keywords, strings, numbers, comments, and function calls.
 */
function highlightJs(code: string): string {
  const keywords =
    /\b(var|let|const|function|return|if|else|for|while|do|switch|case|break|continue|new|typeof|instanceof|in|of|try|catch|finally|throw|class|extends|import|export|default|async|await|yield|this|null|undefined|true|false)\b/g;
  const strings = /(["'`])(?:(?!\1|\\).|\\.)*?\1/g;
  const numbers = /\b(\d+\.?\d*)\b/g;
  const comments = /(\/\/[^\n]*|\/\*[\s\S]*?\*\/)/g;
  const fnCalls = /\b([a-zA-Z_$][\w$]*)\s*\(/g;

  // Tokenize to avoid double-coloring
  type Token = { start: number; end: number; colored: string };
  const tokens: Token[] = [];

  // Comments first (highest priority)
  let m: RegExpExecArray | null;
  while ((m = comments.exec(code)) !== null) {
    tokens.push({
      start: m.index,
      end: m.index + m[0].length,
      colored: `${c.gray}${m[0]}${c.reset}`,
    });
  }

  // Strings
  while ((m = strings.exec(code)) !== null) {
    tokens.push({
      start: m.index,
      end: m.index + m[0].length,
      colored: `${c.green}${m[0]}${c.reset}`,
    });
  }

  // Sort by start position and remove overlaps
  tokens.sort((a, b) => a.start - b.start);
  const merged: Token[] = [];
  for (const tok of tokens) {
    if (merged.length > 0 && tok.start < merged[merged.length - 1].end) {
      continue; // overlaps with previous
    }
    merged.push(tok);
  }

  // Build result, coloring gaps between tokens
  let result = "";
  let pos = 0;
  for (const tok of merged) {
    if (tok.start > pos) {
      // Color the gap (keywords, numbers, function calls)
      result += colorGap(code.slice(pos, tok.start));
    }
    result += tok.colored;
    pos = tok.end;
  }
  if (pos < code.length) {
    result += colorGap(code.slice(pos));
  }

  return result;
}

/** Apply keyword/number/function coloring to a code fragment. */
function colorGap(text: string): string {
  return text
    .replace(
      /\b(var|let|const|function|return|if|else|for|while|do|switch|case|break|continue|new|typeof|instanceof|in|of|try|catch|finally|throw|class|extends|import|export|default|async|await|yield|this)\b/g,
      `${c.magenta}$1${c.reset}`,
    )
    .replace(
      /\b(null|undefined|true|false)\b/g,
      `${c.yellow}$1${c.reset}`,
    )
    .replace(
      /\b(\d+\.?\d*)\b/g,
      `${c.yellow}$1${c.reset}`,
    )
    .replace(
      /\b([a-zA-Z_$][\w$]*)\s*\(/g,
      `${c.cyan}$1${c.reset}(`,
    );
}

/** Format a tool result string with color based on content. */
function formatResult(result: string): string {
  // Error results
  if (result.startsWith("Error:")) {
    return `  ${c.red}${c.bold}error${c.reset} ${c.red}${result.slice(7)}${c.reset}`;
  }

  // Parse [Result: N chars] "preview..."
  const metaMatch = result.match(
    /^\[Result: (\d+) chars\] "(.+)"$/s,
  );
  if (metaMatch) {
    const [, chars, preview] = metaMatch;
    const num = parseInt(chars, 10);
    // Short results: show inline
    if (num <= 80) {
      return `  ${c.dim}→${c.reset} ${c.brightGreen}${preview.replace(/\.\.\.$/,`${c.dim}...${c.reset}`)}${c.reset}`;
    }
    // Longer results: show with size
    return `  ${c.dim}→ ${chars} chars${c.reset} ${c.brightGreen}${preview.replace(/\.\.\.$/,`${c.dim}...${c.reset}`)}${c.reset}`;
  }

  // [Result: undefined]
  if (result === "[Result: undefined]") {
    return `  ${c.dim}→ ok${c.reset}`;
  }

  // Fallback
  const preview = result.length > 120 ? result.slice(0, 117) + "..." : result;
  return `  ${c.dim}→${c.reset} ${preview}`;
}

export function createRlmConsoleRenderer(
  options: RlmConsoleRendererOptions = {},
): RlmConsoleRenderer {
  const verbose = options.verbose ?? false;
  const showCode = options.showCode ?? true;
  const maxCodeLines = options.maxCodeLines ?? 20;
  const stdout = options.stdout ?? process.stdout;
  const stderr = options.stderr ?? process.stderr;

  const write = (stream: NodeJS.WritableStream, text: string) => {
    stream.write(text + "\n");
  };

  return {
    createState: () => ({ sawText: false, turnCount: 0 }),
    handle: (event, state) => {
      // --- Tool Calls ---
      if (event instanceof ToolCallEvent) {
        if (event.tool === "js" && showCode) {
          const code = event.args?.code ?? "";
          const lines = code.split("\n");
          const display =
            lines.length > maxCodeLines
              ? [
                  ...lines.slice(0, maxCodeLines),
                  `${c.dim}  ... ${lines.length - maxCodeLines} more lines${c.reset}`,
                ]
              : lines;

          write(
            stderr,
            `\n${c.blue}${c.bold}js${c.reset} ${c.dim}───────────────────────────────────${c.reset}`,
          );
          for (const line of display) {
            write(stderr, `${c.dim}│${c.reset} ${highlightJs(line)}`);
          }
          write(stderr, `${c.dim}╰─${c.reset}`);
        } else if (verbose) {
          write(
            stderr,
            `${c.blue}${c.bold}» ${event.tool}${c.reset}${c.dim}(${JSON.stringify(event.args)})${c.reset}`,
          );
        } else {
          write(stderr, `${c.blue}${c.bold}» ${event.tool}${c.reset}`);
        }
        return;
      }

      // --- Tool Results ---
      if (event instanceof ToolResultEvent) {
        const line = event.result?.toString?.() ?? String(event.result);
        if (event.tool === "js") {
          write(stderr, formatResult(line));
        } else if (verbose) {
          write(stderr, `${c.dim}│${c.reset} ${line}`);
        }
        return;
      }

      // --- Text (LLM reasoning) ---
      if (event instanceof TextEvent) {
        const text = event.content.replace(/\s+$/, "");
        if (text) {
          write(stdout, text);
        }
        state.sawText = true;
        return;
      }

      // --- Final Response ---
      if (event instanceof FinalResponseEvent) {
        if (!state.sawText) {
          const text = event.content.replace(/\s+$/, "");
          if (text) write(stdout, text);
        }
        return;
      }

      // --- Usage ---
      if (event instanceof UsageEvent) {
        if (verbose) {
          const cost =
            event.cost !== null ? ` ${c.yellow}$${event.cost.toFixed(4)}${c.reset}` : "";
          const cumStr =
            event.cumulative_tokens !== event.total_tokens
              ? ` ${c.dim}(total: ${event.cumulative_tokens} tokens)${c.reset}`
              : "";
          write(
            stderr,
            `  ${c.dim}[${event.total_tokens} tokens${c.reset}${cost}${cumStr}${c.dim}]${c.reset}`,
          );
        }
      }
    },
  };
}

/**
 * Colorized progress logger for RLM sub-agent delegation.
 * Replaces the default console.error tree logging with styled output.
 *
 * Use this to override the default stderr output in registerRlmFunctions:
 *   console.error = createColoredLogger()
 *
 * Or patch it in the example script before creating the agent.
 */
export function patchStderrForRlm(): void {
  const original = console.error.bind(console);

  console.error = (...args: unknown[]) => {
    const msg = args.map(String).join(" ");

    // Match RLM tree lines: ├─ [depth:N] "query" (N chars)
    const depthMatch = msg.match(
      /^(\s*)(├─|└─|│\s+├─)\s*\[depth:(\d+)\]\s*(.+)/,
    );
    if (depthMatch) {
      const [, indent, branch, depth, rest] = depthMatch;
      const d = parseInt(depth, 10);
      const depthColors = [c.cyan, c.magenta, c.yellow, c.blue, c.green];
      const dc = depthColors[d % depthColors.length];

      // "query preview" (N chars)
      const queryMatch = rest.match(/^"(.+?)"\s*\((\d+)\s*chars\)$/);
      if (queryMatch) {
        const [, query, chars] = queryMatch;
        original(
          `${indent}${c.dim}${branch}${c.reset} ${dc}[${depth}]${c.reset} ${c.bold}${query}${c.reset} ${c.dim}(${chars} chars)${c.reset}`,
        );
        return;
      }

      // "done" or "batch complete"
      if (rest.includes("done") || rest.includes("complete")) {
        original(
          `${indent}${c.dim}${branch}${c.reset} ${dc}[${depth}]${c.reset} ${c.green}${rest}${c.reset}`,
        );
        return;
      }

      // llm_batch(N tasks)
      const batchMatch = rest.match(/^llm_batch\((\d+)\s*tasks\)$/);
      if (batchMatch) {
        original(
          `${indent}${c.dim}${branch}${c.reset} ${dc}[${depth}]${c.reset} ${c.brightYellow}batch${c.reset}(${c.bold}${batchMatch[1]}${c.reset} tasks)`,
        );
        return;
      }

      // Batch item: [1/4] "query"
      const itemMatch = rest.match(/^\[(\d+)\/(\d+)\]\s*"(.+)"$/);
      if (itemMatch) {
        const [, idx, total, query] = itemMatch;
        original(
          `${indent}${c.dim}${branch}${c.reset} ${dc}[${idx}/${total}]${c.reset} ${query}`,
        );
        return;
      }

      // Fallback for depth lines
      original(
        `${indent}${c.dim}${branch}${c.reset} ${dc}[${depth}]${c.reset} ${rest}`,
      );
      return;
    }

    // Pass through non-RLM messages
    original(...args);
  };
}
