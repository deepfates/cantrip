import { describe, expect, test } from "bun:test";
import { PassThrough } from "stream";

import { createConsoleRenderer } from "../src/agent/console";
import {
  FinalResponseEvent,
  TextEvent,
  ToolCallEvent,
  ToolResultEvent,
} from "../src/agent/events";

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

describe("console renderer", () => {
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
