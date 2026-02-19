import { describe, expect, test } from "bun:test";
import { createAcpProgressCallback } from "../src/entity/acp/plans";
import type { RlmProgressEvent } from "../src/circle/gate/builtin/call_agent_tools";

/** Captures sessionUpdate calls and extracts plan entries. */
function mockConnection() {
  const updates: any[] = [];
  return {
    updates,
    sessionUpdate(payload: any) {
      updates.push(payload);
      return Promise.resolve();
    },
    /** Returns the entries array from the most recent plan update. */
    get lastEntries() {
      const last = updates[updates.length - 1];
      return last?.update?.entries ?? [];
    },
  };
}

describe("ACP plan updates", () => {
  const sid = "plan-test-session";

  test("sub_agent_start adds an in_progress entry", () => {
    const conn = mockConnection();
    const progress = createAcpProgressCallback(sid, conn as any);

    progress({ type: "sub_agent_start", depth: 1, query: "Find the answer" });

    expect(conn.updates).toHaveLength(1);
    expect(conn.updates[0].sessionId).toBe(sid);
    expect(conn.updates[0].update.sessionUpdate).toBe("plan");
    expect(conn.lastEntries).toHaveLength(1);
    expect(conn.lastEntries[0].status).toBe("in_progress");
    expect(conn.lastEntries[0].content).toContain("Find the answer");
  });

  test("sub_agent_end marks the entry as completed", () => {
    const conn = mockConnection();
    const progress = createAcpProgressCallback(sid, conn as any);

    progress({ type: "sub_agent_start", depth: 1, query: "task A" });
    progress({ type: "sub_agent_end", depth: 1 });

    expect(conn.updates).toHaveLength(2);
    expect(conn.lastEntries).toHaveLength(1);
    expect(conn.lastEntries[0].status).toBe("completed");
  });

  test("long queries are truncated in plan entries", () => {
    const conn = mockConnection();
    const progress = createAcpProgressCallback(sid, conn as any);

    const longQuery = "A".repeat(100);
    progress({ type: "sub_agent_start", depth: 1, query: longQuery });

    const content = conn.lastEntries[0].content;
    expect(content.length).toBeLessThan(100);
    expect(content).toContain("...");
  });

  test("batch lifecycle creates and completes entries", () => {
    const conn = mockConnection();
    const progress = createAcpProgressCallback(sid, conn as any);

    progress({ type: "batch_start", depth: 1, count: 2 });
    expect(conn.lastEntries).toHaveLength(1);
    expect(conn.lastEntries[0].status).toBe("in_progress");
    expect(conn.lastEntries[0].content).toContain("2 parallel");

    progress({
      type: "batch_item",
      depth: 1,
      index: 0,
      total: 2,
      query: "item one",
    });
    expect(conn.lastEntries).toHaveLength(2);
    expect(conn.lastEntries[1].content).toContain("[1/2]");
    expect(conn.lastEntries[1].content).toContain("item one");

    progress({
      type: "batch_item",
      depth: 1,
      index: 1,
      total: 2,
      query: "item two",
    });
    expect(conn.lastEntries).toHaveLength(3);
    expect(conn.lastEntries[2].content).toContain("[2/2]");

    progress({ type: "batch_end", depth: 1 });
    // All entries should now be completed
    for (const entry of conn.lastEntries) {
      expect(entry.status).toBe("completed");
    }
  });

  test("multiple sub-agents accumulate entries", () => {
    const conn = mockConnection();
    const progress = createAcpProgressCallback(sid, conn as any);

    progress({ type: "sub_agent_start", depth: 1, query: "first" });
    progress({ type: "sub_agent_end", depth: 1 });
    progress({ type: "sub_agent_start", depth: 1, query: "second" });

    expect(conn.lastEntries).toHaveLength(2);
    expect(conn.lastEntries[0].status).toBe("completed");
    expect(conn.lastEntries[1].status).toBe("in_progress");
  });

  test("nested sub-agents end in correct order", () => {
    const conn = mockConnection();
    const progress = createAcpProgressCallback(sid, conn as any);

    progress({ type: "sub_agent_start", depth: 1, query: "outer" });
    progress({ type: "sub_agent_start", depth: 2, query: "inner" });
    progress({ type: "sub_agent_end", depth: 2 });

    // Inner should be completed, outer still in_progress
    expect(conn.lastEntries).toHaveLength(2);
    expect(conn.lastEntries[0].status).toBe("in_progress");
    expect(conn.lastEntries[1].status).toBe("completed");

    progress({ type: "sub_agent_end", depth: 1 });
    expect(conn.lastEntries[0].status).toBe("completed");
    expect(conn.lastEntries[1].status).toBe("completed");
  });

  test("each update sends the full entries array", () => {
    const conn = mockConnection();
    const progress = createAcpProgressCallback(sid, conn as any);

    progress({ type: "sub_agent_start", depth: 1, query: "a" });
    progress({ type: "sub_agent_start", depth: 1, query: "b" });

    // Second update should contain both entries
    expect(conn.updates[1].update.entries).toHaveLength(2);
  });
});
