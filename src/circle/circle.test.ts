import { describe, it, expect } from "bun:test";
import { Circle } from "./circle";
import type { BoundGate } from "./gate/gate";

/** Helper: create a minimal BoundGate stub for testing. */
function stubGate(overrides: Partial<BoundGate> & { name: string }): BoundGate {
  return {
    definition: {
      name: overrides.name,
      description: "",
      parameters: {},
    },
    execute: async () => "ok",
    ephemeral: false,
    ...overrides,
  };
}

/** Helper: create a Circle with sensible defaults for testing capabilityDocs. */
function makeCircle(gates: BoundGate[]): ReturnType<typeof Circle> {
  // Always include a done gate so Circle constructor doesn't throw
  const hasDone = gates.some((g) => g.name === "done");
  const allGates = hasDone
    ? gates
    : [
        ...gates,
        stubGate({
          name: "done",
          definition: {
            name: "done",
            description: "Submit final result",
            parameters: { type: "object", properties: { result: { type: "string" } } },
          },
        }),
      ];
  return Circle({ gates: allGates, wards: [{ max_turns: 10 }] });
}

describe("Circle.capabilityDocs", () => {
  it("exists as a method on the circle", () => {
    const circle = makeCircle([]);
    expect(typeof circle.capabilityDocs).toBe("function");
  });

  it("returns empty string when no gates have docs", () => {
    const circle = makeCircle([
      stubGate({ name: "some_tool" }),
    ]);
    expect(circle.capabilityDocs()).toBe("");
  });

  it("gates without docs.section are invisible", () => {
    const circle = makeCircle([
      stubGate({
        name: "invisible",
        docs: { sandbox_name: "invisible", description: "should not appear" },
        // no section → invisible
      }),
    ]);
    expect(circle.capabilityDocs()).toBe("");
  });

  it("gates without docs.sandbox_name are invisible", () => {
    const circle = makeCircle([
      stubGate({
        name: "invisible",
        docs: { section: "HOST FUNCTIONS", description: "should not appear" },
        // no sandbox_name → invisible
      }),
    ]);
    expect(circle.capabilityDocs()).toBe("");
  });

  it("renders a single gate with section header and signature", () => {
    const circle = makeCircle([
      stubGate({
        name: "call_entity",
        docs: {
          section: "HOST FUNCTIONS",
          sandbox_name: "llm_query",
          signature: "llm_query(query: string, context?: any): string",
          description: "Query a sub-LLM.",
        },
      }),
    ]);
    const result = circle.capabilityDocs();
    expect(result).toContain("### HOST FUNCTIONS");
    expect(result).toContain(
      "- `llm_query(query: string, context?: any): string`: Query a sub-LLM.",
    );
  });

  it("falls back to sandbox_name when no signature provided", () => {
    const circle = makeCircle([
      stubGate({
        name: "submit",
        docs: {
          section: "HOST FUNCTIONS",
          sandbox_name: "submit_answer",
          description: "Submit final answer.",
        },
      }),
    ]);
    const result = circle.capabilityDocs();
    expect(result).toContain("- `submit_answer`: Submit final answer.");
  });

  it("groups multiple gates under the same section", () => {
    const circle = makeCircle([
      stubGate({
        name: "call_entity",
        docs: {
          section: "HOST FUNCTIONS",
          sandbox_name: "llm_query",
          signature: "llm_query(query)",
          description: "Query LLM.",
        },
      }),
      stubGate({
        name: "submit",
        docs: {
          section: "HOST FUNCTIONS",
          sandbox_name: "submit_answer",
          signature: "submit_answer(result)",
          description: "Submit answer.",
        },
      }),
    ]);
    const result = circle.capabilityDocs();
    // Only one section header
    const headerCount = (result.match(/### HOST FUNCTIONS/g) || []).length;
    expect(headerCount).toBe(1);
    // Both gates present
    expect(result).toContain("llm_query(query)");
    expect(result).toContain("submit_answer(result)");
  });

  it("renders multiple sections", () => {
    const circle = makeCircle([
      stubGate({
        name: "call_entity",
        docs: {
          section: "HOST FUNCTIONS",
          sandbox_name: "llm_query",
          signature: "llm_query(query)",
          description: "Query LLM.",
        },
      }),
      stubGate({
        name: "browser_goto",
        docs: {
          section: "BROWSER",
          sandbox_name: "goto",
          signature: "goto(url)",
          description: "Navigate to URL.",
        },
      }),
    ]);
    const result = circle.capabilityDocs();
    expect(result).toContain("### HOST FUNCTIONS");
    expect(result).toContain("### BROWSER");
  });

  it("handles empty description gracefully", () => {
    const circle = makeCircle([
      stubGate({
        name: "tool",
        docs: {
          section: "TOOLS",
          sandbox_name: "my_tool",
          signature: "my_tool()",
        },
      }),
    ]);
    const result = circle.capabilityDocs();
    expect(result).toContain("- `my_tool()`: ");
  });

  it("excludes the done gate from docs (done gate has no docs)", () => {
    // The done gate we auto-inject has no docs, so it should be invisible
    const circle = makeCircle([]);
    expect(circle.capabilityDocs()).toBe("");
  });
});
