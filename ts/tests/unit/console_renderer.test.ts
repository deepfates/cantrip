import { describe, expect, test } from "bun:test";
import { PassThrough } from "stream";

import {
  createConsoleRenderer,
  patchStderrForEntities,
} from "../../src/entity/console";
import {
  FinalResponseEvent,
  TextEvent,
  ToolCallEvent,
  ToolResultEvent,
} from "../../src/entity/events";

const createCaptureStream = () => {
  const stream = new PassThrough();
  let output = "";
  stream.on("data", (chunk) => {
    output += chunk.toString();
  });
  return {
    stream,
    getOutput: () => output,
  };
};

/** Capture writes to a fake stream (line-based). */
function capture() {
  const lines: string[] = [];
  const stream = {
    write(chunk: string) {
      lines.push(chunk.replace(/\n$/, ""));
      return true;
    },
  } as unknown as NodeJS.WritableStream;
  return { lines, stream };
}

describe("console renderer (plain)", () => {
  test("prints text to stdout and trims trailing whitespace", () => {
    const stdout = createCaptureStream();
    const stderr = createCaptureStream();
    const renderer = createConsoleRenderer({
      stdout: stdout.stream,
      stderr: stderr.stream,
    });
    const state = renderer.createState();

    renderer.handle(new TextEvent("hello   \n\n"), state);

    expect(stdout.getOutput()).toBe("hello\n");
    expect(stderr.getOutput()).toBe("");
  });

  test("prints final response only when no text was streamed", () => {
    const stdout = createCaptureStream();
    const renderer = createConsoleRenderer({ stdout: stdout.stream });
    const state = renderer.createState();

    renderer.handle(new FinalResponseEvent("final"), state);
    renderer.handle(new TextEvent("streamed"), state);
    renderer.handle(new FinalResponseEvent("ignored"), state);

    expect(stdout.getOutput()).toBe("final\nstreamed\n");
  });

  test("tool events are silent when verbose is false", () => {
    const stdout = createCaptureStream();
    const stderr = createCaptureStream();
    const renderer = createConsoleRenderer({
      stdout: stdout.stream,
      stderr: stderr.stream,
      verbose: false,
    });
    const state = renderer.createState();

    renderer.handle(new ToolCallEvent("bash", {}, "call_1"), state);
    renderer.handle(new ToolResultEvent("bash", "ok", "call_1"), state);

    expect(stdout.getOutput()).toBe("");
    expect(stderr.getOutput()).toBe("» bash\n");
  });

  test("tool events are printed to stderr when verbose is true", () => {
    const stderr = createCaptureStream();
    const renderer = createConsoleRenderer({
      stderr: stderr.stream,
      verbose: true,
    });
    const state = renderer.createState();

    renderer.handle(new ToolCallEvent("bash", {}, "call_1"), state);
    renderer.handle(new ToolResultEvent("bash", "ok", "call_1"), state);

    expect(stderr.getOutput()).toBe("» bash({})\n│ ok\n");
  });
});

describe("console renderer (colors)", () => {
  test("renders js tool call with syntax-highlighted code", () => {
    const out = capture();
    const err = capture();
    const renderer = createConsoleRenderer({
      colors: true,
      stdout: out.stream,
      stderr: err.stream,
    });
    const state = renderer.createState();

    renderer.handle(
      new ToolCallEvent(
        "js",
        { code: 'var x = goto("https://example.com")' },
        "1",
      ),
      state,
    );

    // Should have the "js" header line, at least one code line, and the closing line
    expect(err.lines.length).toBeGreaterThanOrEqual(3);
    // Header contains "js"
    expect(err.lines[0]).toContain("js");
    // Code line contains the code (with ANSI codes)
    const codeLine = err.lines[1];
    expect(codeLine).toContain("goto");
    expect(codeLine).toContain("example.com");
  });

  test("renders non-js tool call as simple line", () => {
    const out = capture();
    const err = capture();
    const renderer = createConsoleRenderer({
      colors: true,
      verbose: true,
      stdout: out.stream,
      stderr: err.stream,
    });
    const state = renderer.createState();

    renderer.handle(new ToolCallEvent("search", { query: "test" }, "1"), state);

    expect(err.lines.length).toBe(1);
    expect(err.lines[0]).toContain("search");
  });

  test("renders result metadata with arrow", () => {
    const out = capture();
    const err = capture();
    const renderer = createConsoleRenderer({
      colors: true,
      stdout: out.stream,
      stderr: err.stream,
    });
    const state = renderer.createState();

    renderer.handle(
      new ToolResultEvent(
        "js",
        '[Result: 42 chars] "Hello world from the browser"',
        "1",
      ),
      state,
    );

    expect(err.lines.length).toBe(1);
    expect(err.lines[0]).toContain("Hello world");
  });

  test("renders undefined result as ok", () => {
    const out = capture();
    const err = capture();
    const renderer = createConsoleRenderer({
      colors: true,
      stdout: out.stream,
      stderr: err.stream,
    });
    const state = renderer.createState();

    renderer.handle(
      new ToolResultEvent("js", "[Result: undefined]", "1"),
      state,
    );

    expect(err.lines.length).toBe(1);
    expect(err.lines[0]).toContain("ok");
  });

  test("renders error result in red", () => {
    const out = capture();
    const err = capture();
    const renderer = createConsoleRenderer({
      colors: true,
      stdout: out.stream,
      stderr: err.stream,
    });
    const state = renderer.createState();

    renderer.handle(
      new ToolResultEvent("js", "Error: something broke", "1", true),
      state,
    );

    expect(err.lines.length).toBe(1);
    // Contains the ANSI red code
    expect(err.lines[0]).toContain("\x1b[31m");
    expect(err.lines[0]).toContain("something broke");
  });

  test("renders text events to stdout", () => {
    const out = capture();
    const err = capture();
    const renderer = createConsoleRenderer({
      colors: true,
      stdout: out.stream,
      stderr: err.stream,
    });
    const state = renderer.createState();

    renderer.handle(new TextEvent("I'll analyze the page now."), state);

    expect(out.lines.length).toBe(1);
    expect(out.lines[0]).toContain("analyze the page");
    expect(state.sawText).toBe(true);
  });

  test("multi-line code is properly displayed", () => {
    const out = capture();
    const err = capture();
    const renderer = createConsoleRenderer({
      colors: true,
      stdout: out.stream,
      stderr: err.stream,
    });
    const state = renderer.createState();

    const code = [
      'goto("https://example.com")',
      "var title = title()",
      "var links = evaluate(\"document.querySelectorAll('a').length\")",
      "submit_answer({ title: title, links: links })",
    ].join("\n");

    renderer.handle(new ToolCallEvent("js", { code }, "1"), state);

    // Header + 4 code lines + closing = 6
    expect(err.lines.length).toBe(6);
  });

  test("truncates code beyond maxCodeLines", () => {
    const out = capture();
    const err = capture();
    const renderer = createConsoleRenderer({
      colors: true,
      maxCodeLines: 3,
      stdout: out.stream,
      stderr: err.stream,
    });
    const state = renderer.createState();

    const code = Array.from({ length: 10 }, (_, i) => `var x${i} = ${i}`).join(
      "\n",
    );

    renderer.handle(new ToolCallEvent("js", { code }, "1"), state);

    // Header + 3 lines + "... 7 more lines" + closing = 6
    expect(err.lines.length).toBe(6);
    // Strip ANSI codes before checking content (numbers get colorized)
    const stripped = err.lines[4].replace(/\x1b\[[0-9;]*m/g, "");
    expect(stripped).toContain("7 more lines");
  });

  test("FinalResponseEvent only prints if no text was seen", () => {
    const out = capture();
    const err = capture();
    const renderer = createConsoleRenderer({
      colors: true,
      stdout: out.stream,
      stderr: err.stream,
    });
    const state = renderer.createState();

    // With prior text
    renderer.handle(new TextEvent("hello"), state);
    renderer.handle(new FinalResponseEvent("hello"), state);
    expect(out.lines.length).toBe(1); // Only the TextEvent

    // Without prior text
    const state2 = renderer.createState();
    renderer.handle(new FinalResponseEvent("final answer"), state2);
    expect(out.lines).toContain("final answer");
  });
});

describe("patchStderrForEntities", () => {
  test("colorizes depth lines", () => {
    const lines: string[] = [];
    const original = console.error;
    console.error = (...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    };

    patchStderrForEntities();

    // Simulate depth logging
    console.error('├─ [depth:1] "summarize this page" (500 chars)');
    console.error("└─ [depth:1] done");

    // Restore
    console.error = original;

    expect(lines.length).toBe(2);
    // Should contain ANSI codes (colorized)
    expect(lines[0]).toContain("\x1b[");
    expect(lines[0]).toContain("summarize this page");
    expect(lines[1]).toContain("done");
  });
});
