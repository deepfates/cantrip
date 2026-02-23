import { describe, expect, test } from "bun:test";

import {
  cantripGates,
  CantripHandleStore,
} from "../../../src/circle/gate/builtin/cantrip";
import type { CantripMediumConfig } from "../../../src/circle/gate/builtin/cantrip";
import type { GateDefinition, ToolChoice } from "../../../src/crystal/crystal";
import type { Medium } from "../../../src/circle/medium";
import { done } from "../../../src/circle/gate/builtin/done";
import { buildCapabilityDocs } from "../../../src/circle/circle";
import type { CircleExecuteResult } from "../../../src/circle/circle";

class TestMedium implements Medium {
  disposed = false;
  constructor(public readonly name: string) {}
  async init(): Promise<void> {}
  crystalView(): { tool_definitions: GateDefinition[]; tool_choice: ToolChoice } {
    return { tool_definitions: [], tool_choice: "auto" };
  }
  async execute(): Promise<CircleExecuteResult> {
    return { messages: [], gate_calls: [] };
  }
  async dispose(): Promise<void> { this.disposed = true; }
  capabilityDocs(): string { return this.name; }
}

function gateByName(gates: any[], sandboxName: string) {
  const gate = gates.find((g) => g.docs?.sandbox_name === sandboxName);
  if (!gate) throw new Error(`Gate with sandbox_name "${sandboxName}" not found`);
  return gate;
}

function setup() {
  const createdMediums: TestMedium[] = [];

  const config: CantripMediumConfig = {
    mediums: {
      js: (opts?: any) => {
        const medium = new TestMedium("js");
        createdMediums.push(medium);
        return medium;
      },
      bash: (opts?: any) => {
        const medium = new TestMedium("bash");
        createdMediums.push(medium);
        return medium;
      },
      browser: () => {
        const medium = new TestMedium("browser");
        createdMediums.push(medium);
        return medium;
      },
    },
    gates: {
      basic: [done],
    },
    default_wards: [{ max_turns: 5 }],
  };

  const { gates, overrides } = cantripGates(config);

  return { gates, overrides, createdMediums, config };
}

describe("cantripGates — isomorphic API", () => {
  // ── Shape ─────────────────────────────────────────────────────────

  test("returns cantrip, cast, and dispose gates", () => {
    const { gates } = setup();
    const names = gates.map((g) => g.docs?.sandbox_name).filter(Boolean);
    expect(names).toContain("cantrip");
    expect(names).toContain("cast");
    expect(names).toContain("dispose");
    expect(names.length).toBe(3);
  });

  test("all gates have CANTRIP CONSTRUCTION section in docs", () => {
    const { gates } = setup();
    for (const gate of gates) {
      expect(gate.docs?.section).toBe("CANTRIP CONSTRUCTION");
    }
  });

  test("gates produce CANTRIP CONSTRUCTION docs via buildCapabilityDocs", () => {
    const { gates } = setup();
    const docs = buildCapabilityDocs(gates);
    expect(docs).toContain("CANTRIP CONSTRUCTION");
    expect(docs).toContain("cantrip");
    expect(docs).toContain("cast");
    expect(docs).toContain("dispose");
  });

  // ── cantrip() — validation ───────────────────────────────────────

  test("cantrip() without circle creates a leaf handle", async () => {
    const { gates, overrides } = setup();
    const gate = gateByName(gates, "cantrip");
    const handle = await gate.execute({ crystal: "anthropic/claude-3.5-haiku", call: "You are helpful" }, overrides);
    expect(Number(handle)).toBeGreaterThan(0);
  });

  test("cantrip() with circle creates a full handle and medium", async () => {
    const { gates, overrides, createdMediums } = setup();
    const gate = gateByName(gates, "cantrip");
    const handle = await gate.execute({
      crystal: "anthropic/claude-3.5-haiku",
      call: "Run commands",
      circle: {
        medium: "bash",
        gates: ["basic"],
        wards: [{ max_turns: 3 }],
      },
    }, overrides);
    expect(Number(handle)).toBeGreaterThan(0);
    expect(createdMediums.length).toBe(1);
    expect(createdMediums[0].name).toBe("bash");
  });

  test("cantrip() rejects empty crystal name", async () => {
    const { gates, overrides } = setup();
    await expect(
      gateByName(gates, "cantrip").execute({ crystal: "", call: "test" }, overrides),
    ).rejects.toThrow(/requires a crystal/);
  });

  test("cantrip() rejects empty call", async () => {
    const { gates, overrides } = setup();
    await expect(
      gateByName(gates, "cantrip").execute({ crystal: "anthropic/claude-3.5-haiku", call: "" }, overrides),
    ).rejects.toThrow(/requires a call/);
  });

  test("cantrip() rejects unknown medium name", async () => {
    const { gates, overrides } = setup();
    await expect(
      gateByName(gates, "cantrip").execute({
        crystal: "anthropic/claude-3.5-haiku",
        call: "test",
        circle: { medium: "nonexistent" },
      }, overrides),
    ).rejects.toThrow(/Unknown medium/);
  });

  test("cantrip() rejects unknown gate set names", async () => {
    const { gates, overrides } = setup();
    await expect(
      gateByName(gates, "cantrip").execute({
        crystal: "anthropic/claude-3.5-haiku",
        call: "test",
        circle: { gates: ["nonexistent"], wards: [{ max_turns: 3 }] },
      }, overrides),
    ).rejects.toThrow(/Unknown gate set/);
  });

  test("cantrip() circle requires at least one ward", async () => {
    const config: CantripMediumConfig = {
      mediums: { js: () => new TestMedium("js") },
    };
    const { gates, overrides } = cantripGates(config);
    await expect(
      gateByName(gates, "cantrip").execute({
        crystal: "anthropic/claude-3.5-haiku",
        call: "test",
        circle: { wards: [] },
      }, overrides),
    ).rejects.toThrow(/at least one ward/);
  });

  // ── cast() — validation ──────────────────────────────────────────

  test("cast() rejects missing intent", async () => {
    const { gates, overrides } = setup();
    const cantripHandle = Number(
      await gateByName(gates, "cantrip").execute(
        { crystal: "anthropic/claude-3.5-haiku", call: "test" },
        overrides,
      ),
    );
    await expect(
      gateByName(gates, "cast").execute(
        { cantrip: cantripHandle, intent: "" },
        overrides,
      ),
    ).rejects.toThrow(/intent/);
  });

  test("cast() rejects invalid handle", async () => {
    const { gates, overrides } = setup();
    await expect(
      gateByName(gates, "cast").execute({ cantrip: 9999, intent: "hi" }, overrides),
    ).rejects.toThrow(/Invalid cantrip handle/);
  });

  // ── dispose() ────────────────────────────────────────────────────

  test("dispose() removes handle and prevents reuse", async () => {
    const { gates, overrides } = setup();
    const cantripHandle = Number(
      await gateByName(gates, "cantrip").execute(
        { crystal: "anthropic/claude-3.5-haiku", call: "test" },
        overrides,
      ),
    );
    await gateByName(gates, "dispose").execute({ cantrip: cantripHandle }, overrides);

    await expect(
      gateByName(gates, "dispose").execute({ cantrip: cantripHandle }, overrides),
    ).rejects.toThrow(/Invalid cantrip handle/);
  });

  test("dispose() on full cantrip disposes its circle", async () => {
    const { gates, overrides, createdMediums } = setup();
    const cantripHandle = Number(
      await gateByName(gates, "cantrip").execute({
        crystal: "anthropic/claude-3.5-haiku",
        call: "test",
        circle: { medium: "js", gates: ["basic"] },
      }, overrides),
    );
    expect(createdMediums[0].disposed).toBe(false);
    await gateByName(gates, "dispose").execute({ cantrip: cantripHandle }, overrides);
  });

  // ── Handle store ─────────────────────────────────────────────────

  test("handle store rejects non-numeric handles", () => {
    const store = new CantripHandleStore();
    expect(() => store.get("not a number" as any)).toThrow(/finite number/);
    expect(() => store.get(NaN)).toThrow(/finite number/);
    expect(() => store.get(Infinity)).toThrow(/finite number/);
  });
});
