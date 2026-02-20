import { describe, expect, test } from "bun:test";
import { mapEvent } from "../../src/entity/acp/events";
import {
  TextEvent,
  ThinkingEvent,
  ToolCallEvent,
  ToolResultEvent,
  FinalResponseEvent,
  StepStartEvent,
  StepCompleteEvent,
  UsageEvent,
  HiddenUserMessageEvent,
} from "../../src/entity/events";

/** Captures sessionUpdate calls for assertions. */
function mockConnection() {
  const updates: any[] = [];
  return {
    updates,
    sessionUpdate(payload: any) {
      updates.push(payload);
      return Promise.resolve();
    },
  };
}

describe("ACP event mapping", () => {
  const sid = "test-session-1";

  test("TextEvent maps to agent_message_chunk", async () => {
    const conn = mockConnection();
    const result = await mapEvent(sid, new TextEvent("hello"), conn as any);

    expect(result).toBe(false);
    expect(conn.updates).toHaveLength(1);
    expect(conn.updates[0]).toEqual({
      sessionId: sid,
      update: {
        sessionUpdate: "agent_message_chunk",
        content: { type: "text", text: "hello" },
      },
    });
  });

  test("ThinkingEvent maps to agent_thought_chunk", async () => {
    const conn = mockConnection();
    const result = await mapEvent(
      sid,
      new ThinkingEvent("thinking..."),
      conn as any,
    );

    expect(result).toBe(false);
    expect(conn.updates).toHaveLength(1);
    expect(conn.updates[0].update.sessionUpdate).toBe("agent_thought_chunk");
    expect(conn.updates[0].update.content.text).toBe("thinking...");
  });

  test("ToolCallEvent maps to tool_call with kind and locations", async () => {
    const conn = mockConnection();
    const event = new ToolCallEvent(
      "read",
      { file_path: "/src/index.ts" },
      "tc-1",
    );
    const result = await mapEvent(sid, event, conn as any);

    expect(result).toBe(false);
    expect(conn.updates).toHaveLength(1);
    const update = conn.updates[0].update;
    expect(update.sessionUpdate).toBe("tool_call");
    expect(update.toolCallId).toBe("tc-1");
    expect(update.kind).toBe("read");
    expect(update.status).toBe("in_progress");
    expect(update.locations).toEqual([{ path: "/src/index.ts" }]);
    expect(update.title).toBe("Reading /src/index.ts");
  });

  test("ToolCallEvent for bash includes code content block", async () => {
    const conn = mockConnection();
    const event = new ToolCallEvent("bash", { command: "ls -la" }, "tc-bash");
    await mapEvent(sid, event, conn as any);

    const update = conn.updates[0].update;
    expect(update.title).toBe("$ ls -la");
    expect(update.content).toEqual([
      {
        type: "content",
        content: { type: "text", text: "```sh\nls -la\n```" },
      },
    ]);
  });

  test("ToolCallEvent for js includes code content block", async () => {
    const conn = mockConnection();
    const event = new ToolCallEvent(
      "js",
      { code: "console.log('hi')" },
      "tc-js",
    );
    await mapEvent(sid, event, conn as any);

    const update = conn.updates[0].update;
    expect(update.content).toEqual([
      {
        type: "content",
        content: {
          type: "text",
          text: "```js\nconsole.log('hi')\n```",
        },
      },
    ]);
  });

  test("ToolCallEvent for edit includes diff content block", async () => {
    const conn = mockConnection();
    const event = new ToolCallEvent(
      "edit",
      {
        file_path: "/src/foo.ts",
        old_string: "const a = 1;",
        new_string: "const a = 2;",
      },
      "tc-edit",
    );
    await mapEvent(sid, event, conn as any);

    const update = conn.updates[0].update;
    expect(update.content).toEqual([
      {
        type: "diff",
        path: "/src/foo.ts",
        oldText: "const a = 1;",
        newText: "const a = 2;",
      },
    ]);
  });

  test("ToolCallEvent for read has no content blocks", async () => {
    const conn = mockConnection();
    const event = new ToolCallEvent(
      "read",
      { file_path: "/src/index.ts" },
      "tc-read",
    );
    await mapEvent(sid, event, conn as any);

    const update = conn.updates[0].update;
    expect(update.content).toBeUndefined();
  });

  test("ToolResultEvent maps to tool_call_update (success)", async () => {
    const conn = mockConnection();
    const event = new ToolResultEvent("read", "file contents here", "tc-1");
    const result = await mapEvent(sid, event, conn as any);

    expect(result).toBe(false);
    expect(conn.updates).toHaveLength(1);
    const update = conn.updates[0].update;
    expect(update.sessionUpdate).toBe("tool_call_update");
    expect(update.toolCallId).toBe("tc-1");
    expect(update.status).toBe("completed");
    expect(update.rawOutput).toBe("file contents here");
  });

  test("tool_call_update preserves edit diff from tool_call", async () => {
    const conn = mockConnection();
    // First send the tool_call with a diff
    await mapEvent(
      sid,
      new ToolCallEvent(
        "edit",
        {
          file_path: "/src/foo.ts",
          old_string: "const a = 1;",
          new_string: "const a = 2;",
        },
        "tc-edit-preserve",
      ),
      conn as any,
    );
    // Then send the result
    await mapEvent(
      sid,
      new ToolResultEvent(
        "edit",
        "Replaced 1 occurrence(s) in foo.ts",
        "tc-edit-preserve",
      ),
      conn as any,
    );

    const update = conn.updates[1].update;
    expect(update.sessionUpdate).toBe("tool_call_update");
    expect(update.content).toEqual([
      {
        type: "diff",
        path: "/src/foo.ts",
        oldText: "const a = 1;",
        newText: "const a = 2;",
      },
      {
        type: "content",
        content: {
          type: "text",
          text: "Replaced 1 occurrence(s) in foo.ts",
        },
      },
    ]);
  });

  test("tool_call_update preserves bash code block from tool_call", async () => {
    const conn = mockConnection();
    await mapEvent(
      sid,
      new ToolCallEvent("bash", { command: "echo hello" }, "tc-bash-preserve"),
      conn as any,
    );
    await mapEvent(
      sid,
      new ToolResultEvent("bash", "hello\n", "tc-bash-preserve"),
      conn as any,
    );

    const update = conn.updates[1].update;
    expect(update.content).toEqual([
      {
        type: "content",
        content: { type: "text", text: "```sh\necho hello\n```" },
      },
      {
        type: "content",
        content: { type: "text", text: "hello\n" },
      },
    ]);
  });

  test("tool_call_update without prior input content has result only", async () => {
    const conn = mockConnection();
    // read tool has no input content
    await mapEvent(
      sid,
      new ToolCallEvent(
        "read",
        { file_path: "/src/index.ts" },
        "tc-read-noinput",
      ),
      conn as any,
    );
    await mapEvent(
      sid,
      new ToolResultEvent("read", "file contents", "tc-read-noinput"),
      conn as any,
    );

    const update = conn.updates[1].update;
    expect(update.content).toEqual([
      {
        type: "content",
        content: { type: "text", text: "file contents" },
      },
    ]);
  });

  test("ToolResultEvent maps to tool_call_update (error)", async () => {
    const conn = mockConnection();
    const event = new ToolResultEvent(
      "bash",
      "command not found",
      "tc-2",
      true,
    );
    const result = await mapEvent(sid, event, conn as any);

    expect(result).toBe(false);
    const update = conn.updates[0].update;
    expect(update.status).toBe("failed");
  });

  test("FinalResponseEvent returns true without sending update (already streamed)", async () => {
    const conn = mockConnection();
    const result = await mapEvent(
      sid,
      new FinalResponseEvent("done!"),
      conn as any,
    );

    expect(result).toBe(true);
    expect(conn.updates).toHaveLength(0);
  });

  test("ToolCallEvent for done includes message content block", async () => {
    const conn = mockConnection();
    const result = await mapEvent(
      sid,
      new ToolCallEvent("done", { message: "Task completed successfully!" }, "tc-done"),
      conn as any,
    );

    expect(result).toBe(false);
    expect(conn.updates).toHaveLength(1);
    
    const update = conn.updates[0];
    expect(update.update.sessionUpdate).toBe("tool_call");
    expect(update.update.toolCallId).toBe("tc-done");
    expect(update.update.content).toBeDefined();
    expect(update.update.content).toEqual([
      {
        type: "content",
        content: { type: "text", text: "Task completed successfully!" },
      },
    ]);
  });

  test("unmapped events return false with no updates", async () => {
    const conn = mockConnection();

    expect(
      await mapEvent(sid, new StepStartEvent("s1", "step", 1), conn as any),
    ).toBe(false);
    expect(
      await mapEvent(
        sid,
        new StepCompleteEvent("s1", "completed", 100),
        conn as any,
      ),
    ).toBe(false);
    expect(
      await mapEvent(
        sid,
        new UsageEvent({
          prompt_tokens: 10,
          completion_tokens: 5,
          total_tokens: 15,
        }),
        conn as any,
      ),
    ).toBe(false);
    expect(
      await mapEvent(sid, new HiddenUserMessageEvent("hidden"), conn as any),
    ).toBe(false);

    expect(conn.updates).toHaveLength(0);
  });
});
