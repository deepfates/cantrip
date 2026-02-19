// cantrip-migration: no Agent usage — tests the console renderer (pure event → string)
import { describe, test, expect } from "bun:test";
import {
  createRlmConsoleRenderer,
  patchStderrForRlm,
} from "../src/circle/gate/builtin/call_agent_console";
import {
  ToolCallEvent,
  ToolResultEvent,
  TextEvent,
  FinalResponseEvent,
} from "../src/entity/events";

describe("RLM console renderer", () => {
  /** Capture writes to a fake stream. */
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

  test("renders js tool call with syntax-highlighted code", () => {
    const out = capture();
    const err = capture();
    const renderer = createRlmConsoleRenderer({
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
    const renderer = createRlmConsoleRenderer({
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
    const renderer = createRlmConsoleRenderer({
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
    const renderer = createRlmConsoleRenderer({
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
    const renderer = createRlmConsoleRenderer({
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
    const renderer = createRlmConsoleRenderer({
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
    const renderer = createRlmConsoleRenderer({
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
    const renderer = createRlmConsoleRenderer({
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
    const renderer = createRlmConsoleRenderer({
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

describe("patchStderrForRlm", () => {
  test("colorizes depth lines", () => {
    const lines: string[] = [];
    const original = console.error;
    console.error = (...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    };

    patchStderrForRlm();

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
