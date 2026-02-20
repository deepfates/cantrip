import { describe, test, expect } from "bun:test";
import { call_entity } from "../src/circle/gate/builtin/call_entity_gate";

describe("call_entity gate factory", () => {
  test("returns a BoundGate at depth < max_depth", () => {
    const gate = call_entity({ max_depth: 2, depth: 0 });
    expect(gate).not.toBeNull();
    expect(gate!.name).toBe("call_entity");
    expect(gate!.definition.name).toBe("call_entity");
    expect(gate!.docs?.sandbox_name).toBe("llm_query");
  });

  test("returns null at depth >= max_depth (COMP-6)", () => {
    const gate = call_entity({ max_depth: 2, depth: 2 });
    expect(gate).toBeNull();
  });

  test("returns null at depth > max_depth (COMP-6)", () => {
    const gate = call_entity({ max_depth: 1, depth: 3 });
    expect(gate).toBeNull();
  });

  test("defaults max_depth to 2", () => {
    const gate0 = call_entity({ depth: 0 });
    const gate1 = call_entity({ depth: 1 });
    const gate2 = call_entity({ depth: 2 });
    expect(gate0).not.toBeNull();
    expect(gate1).not.toBeNull();
    expect(gate2).toBeNull();
  });

  test("has correct gate docs", () => {
    const gate = call_entity();
    expect(gate!.docs).toBeDefined();
    expect(gate!.docs!.sandbox_name).toBe("llm_query");
    expect(gate!.docs!.signature).toContain("llm_query");
    expect(gate!.docs!.examples!.length).toBeGreaterThan(0);
  });

  test("gate definition has correct structure", () => {
    const gate = call_entity({ depth: 0 });
    expect(gate).not.toBeNull();
    const def = gate!.definition;
    expect(def.name).toBe("call_entity");
    expect(def.description).toBeTruthy();
    expect(def.parameters).toBeDefined();
    expect((def.parameters as any).properties.query).toBeDefined();
    expect((def.parameters as any).required).toContain("query");
  });

  test("ephemeral is false", () => {
    const gate = call_entity({ depth: 0 });
    expect(gate!.ephemeral).toBe(false);
  });
});
