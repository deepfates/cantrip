import { cantrip } from "../../../cantrip/cantrip";
import type { BaseChatModel } from "../../../crystal/crystal";
import { completionText } from "../../../crystal/views";
import { ChatOpenRouter } from "../../../crystal/providers/openrouter/chat";
import { Circle } from "../../circle";
import type { BoundGate } from "../gate";
import type { Medium } from "../../medium";
import type { Ward } from "../../ward";
import type { Loom } from "../../../loom/loom";
import type { DependencyOverrides } from "../depends";
import { rawGate } from "../raw";
import { Depends } from "../depends";
import { progressBinding } from "./call_entity_gate";
import type { ProgressCallback } from "../../../entity/progress";

// ── Types ────────────────────────────────────────────────────────────

export type CantripMediumConfig = {
  /** Available medium factories, keyed by name. */
  mediums: Record<string, (...args: any[]) => Medium>;
  /** Available gate sets, keyed by name. Entity requests them in circle config. */
  gates?: Record<string, BoundGate[]>;
  /** Shared loom for parent + children. */
  loom?: Loom;
  /** Default wards applied to all child circles. */
  default_wards?: Ward[];
  /** Dependency overrides forwarded to child cantrips (for gates with DI like repo gates). */
  dependency_overrides?: DependencyOverrides;
};

// ── Handle Store ─────────────────────────────────────────────────────

type CantripRecord =
  | { kind: "full"; crystal: BaseChatModel; call: string; circle: ReturnType<typeof Circle> }
  | { kind: "leaf"; crystal: BaseChatModel; call: string };

export class CantripHandleStore {
  private nextId = 1;
  private table = new Map<number, CantripRecord>();

  create(record: CantripRecord): number {
    const id = this.nextId++;
    this.table.set(id, record);
    return id;
  }

  get(handle: unknown): { id: number; record: CantripRecord } {
    const id = this.asHandle(handle);
    const record = this.table.get(id);
    if (!record) {
      throw new Error(`Invalid cantrip handle #${id}`);
    }
    return { id, record };
  }

  /** Remove a handle from the table (after cast auto-disposes, or manual dispose). */
  remove(handle: unknown): CantripRecord {
    const id = this.asHandle(handle);
    const record = this.table.get(id);
    if (!record) {
      throw new Error(`Invalid cantrip handle #${id}`);
    }
    this.table.delete(id);
    return record;
  }

  private asHandle(handle: unknown): number {
    // Gate results pass through serializeBoundGate which stringifies numbers.
    // Accept the string form so entity code like `cast(cantrip({...}), intent)` works
    // without requiring parseInt() on the handle.
    if (typeof handle === "string") {
      const n = Number(handle);
      if (Number.isFinite(n)) return n;
    }
    if (typeof handle !== "number" || !Number.isFinite(handle)) {
      throw new Error(`Cantrip handle must be a finite number, got: ${typeof handle}`);
    }
    return handle;
  }
}

// ── Dependencies ─────────────────────────────────────────────────────

export function getCantripHandleStore(): CantripHandleStore {
  throw new Error("Override via dependency_overrides");
}

export function getCantripConfig(): CantripMediumConfig {
  throw new Error("Override via dependency_overrides");
}

export function getCantripLoom(): Loom | undefined {
  throw new Error("Override via dependency_overrides");
}

const handlesDep = new Depends(getCantripHandleStore);
const configDep = new Depends(getCantripConfig);
const loomDep = new Depends(getCantripLoom);

export {
  handlesDep as getCantripHandleStoreDep,
  configDep as getCantripConfigDep,
  loomDep as getCantripLoomDep,
};

// ── Helpers ──────────────────────────────────────────────────────────

const MAX_RESULT_CHARS = 10_000;

function truncateResult(output: string): string {
  if (output.length <= MAX_RESULT_CHARS) return output;
  return output.slice(0, MAX_RESULT_CHARS) + "\n[truncated]";
}

function resolveGateSets(
  names: string[],
  registry?: Record<string, BoundGate[]>,
): BoundGate[] {
  if (!names.length) return [];
  if (!registry) {
    throw new Error("No gate sets configured in this circle");
  }
  const gates: BoundGate[] = [];
  for (const name of names) {
    const set = registry[name];
    if (!set) {
      throw new Error(`Unknown gate set "${name}"`);
    }
    gates.push(...set);
  }
  return gates;
}

function buildWardList(
  defaults: Ward[] | undefined,
  provided: Ward[],
): Ward[] {
  const wards: Ward[] = [];
  if (defaults) {
    for (const entry of defaults) {
      wards.push(cloneWard(entry));
    }
  }
  for (const entry of provided) {
    wards.push(entry);
  }
  return wards;
}

function cloneWard(ward: Ward): Ward {
  const cloned: Ward = {};
  if (ward.max_turns !== undefined) cloned.max_turns = ward.max_turns;
  if (ward.require_done_tool !== undefined) {
    cloned.require_done_tool = ward.require_done_tool;
  }
  if (ward.max_depth !== undefined) cloned.max_depth = ward.max_depth;
  if (ward.exclude_gates) {
    cloned.exclude_gates = [...ward.exclude_gates];
  }
  return cloned;
}

function normalizeWard(raw: unknown): Ward {
  if (!raw || typeof raw !== "object") {
    throw new Error("wards entries must be objects");
  }
  const src = raw as Record<string, unknown>;
  const ward: Ward = {};

  if (src.max_turns !== undefined) {
    const value = Number(src.max_turns);
    if (!Number.isFinite(value)) {
      throw new Error("ward.max_turns must be a finite number");
    }
    ward.max_turns = value;
  }
  if (src.require_done !== undefined) {
    ward.require_done_tool = Boolean(src.require_done);
  }
  if (src.require_done_tool !== undefined) {
    ward.require_done_tool = Boolean(src.require_done_tool);
  }
  if (src.max_depth !== undefined) {
    const value = Number(src.max_depth);
    if (!Number.isFinite(value)) {
      throw new Error("ward.max_depth must be a finite number");
    }
    ward.max_depth = value;
  }
  if (src.exclude_gates !== undefined) {
    if (!Array.isArray(src.exclude_gates)) {
      throw new Error("ward.exclude_gates must be an array of strings");
    }
    ward.exclude_gates = src.exclude_gates.map((g) => {
      if (typeof g !== "string" || !g) {
        throw new Error("ward.exclude_gates must contain strings");
      }
      return g;
    });
  }

  return ward;
}

// ── Gates ────────────────────────────────────────────────────────────

const SECTION = "CANTRIP CONSTRUCTION";

/**
 * cantrip(config) — create a cantrip and return a handle.
 *
 * This is the same cantrip() function application developers use, projected
 * into the medium so entity code matches the real API. Crystal is any
 * OpenRouter model ID string. Mediums are referenced by name from the
 * host-configured registry.
 *
 * With circle config: creates a full cantrip (entity loop, medium, gates, wards).
 * Without circle: creates a leaf cantrip (single LLM call, no entity loop).
 */
const cantripCreateGate = rawGate<{
  crystal: string;
  call: string;
  circle?: {
    medium?: string;
    medium_opts?: Record<string, unknown>;
    gates?: string[];
    wards?: unknown[];
  };
}>(
  {
    name: "cantrip_create",
    description: "Create a cantrip from a config object and return a handle.",
    parameters: {
      type: "object",
      properties: {
        crystal: { type: "string", description: "Model name (any OpenRouter model ID, e.g. \"anthropic/claude-3.5-haiku\")." },
        call: { type: "string", description: "System prompt for the child entity." },
        circle: {
          type: "object",
          description: "Circle config. Omit for a leaf cantrip (single LLM call).",
          properties: {
            medium: { type: "string", description: "Medium name (e.g. \"bash\", \"js\", \"browser\")." },
            medium_opts: { type: "object", description: "Options passed to the medium factory." },
            gates: {
              type: "array",
              items: { type: "string" },
              description: "Gate set names to include.",
            },
            wards: {
              type: "array",
              items: { type: "object" },
              description: "Ward objects (e.g. { max_turns: 10 }).",
            },
          },
          additionalProperties: false,
        },
      },
      required: ["crystal", "call"],
      additionalProperties: false,
    },
  },
  async ({ crystal: crystalName, call, circle: circleConfig }, deps) => {
    const handles = deps.handles as CantripHandleStore;
    const config = deps.config as CantripMediumConfig;

    if (!crystalName) throw new Error("cantrip() requires a crystal (model name)");
    if (!call) throw new Error("cantrip() requires a call (system prompt)");

    // Entity picks any model by name — we create an OpenRouter crystal on the fly.
    const crystal = new ChatOpenRouter({ model: crystalName });

    // Leaf cantrip — no circle, single LLM call
    if (!circleConfig) {
      return handles.create({ kind: "leaf", crystal, call });
    }

    // Full cantrip — construct medium, circle, the works
    let medium: Medium | undefined;

    if (circleConfig.medium) {
      const factory = config.mediums[circleConfig.medium];
      if (!factory) {
        throw new Error(
          `Unknown medium "${circleConfig.medium}". Available: ${Object.keys(config.mediums).join(", ")}`,
        );
      }
      medium = circleConfig.medium_opts ? factory(circleConfig.medium_opts) : factory();
    }

    const gateSets = resolveGateSets(circleConfig.gates ?? [], config.gates);
    const normalizedWards = (circleConfig.wards ?? []).map((w) => normalizeWard(w));
    const wards = buildWardList(config.default_wards, normalizedWards);
    if (wards.length === 0) {
      throw new Error("cantrip() circle requires at least one ward");
    }

    try {
      const circle = Circle({
        medium,
        gates: gateSets,
        wards,
      });
      return handles.create({ kind: "full", crystal, call, circle });
    } catch (err) {
      if (medium) {
        try { await medium.dispose(); } catch { /* original error has context */ }
      }
      throw err;
    }
  },
  { dependencies: { handles: handlesDep, config: configDep } },
);
cantripCreateGate.docs = {
  sandbox_name: "cantrip",
  signature: "cantrip({ crystal, call, circle? }): handle",
  description: "Create a cantrip. With circle: full entity run. Without: single LLM call.",
  section: SECTION,
};

/**
 * cast(cantrip, intent) — cast a cantrip and return the result.
 *
 * For full cantrips: runs the entity loop, returns the answer, auto-disposes.
 * For leaf cantrips: makes one LLM call (crystal + call + intent), returns the text.
 *
 * The handle is consumed — you can't cast the same cantrip twice.
 * (Just like the real API: cantrip().cast() creates a fresh run each time.)
 */
const cantripCastGate = rawGate<{ cantrip: number; intent: string }>(
  {
    name: "cantrip_cast",
    description: "Cast a cantrip and return its result string.",
    parameters: {
      type: "object",
      properties: {
        cantrip: { type: "integer", description: "Cantrip handle from cantrip()." },
        intent: { type: "string", description: "The intent to cast — what you want done." },
      },
      required: ["cantrip", "intent"],
      additionalProperties: false,
    },
  },
  async ({ cantrip: cantripHandle, intent }, deps) => {
    const handles = deps.handles as CantripHandleStore;
    const sharedLoom = deps.loom as Loom | undefined;
    const config = deps.config as CantripMediumConfig;
    const progress = deps.onProgress as ProgressCallback | null;

    if (!intent) throw new Error("cast() requires an intent string");

    const { record } = handles.get(cantripHandle);

    // ── Leaf cantrip: single LLM call, no entity loop ──
    if (record.kind === "leaf") {
      handles.remove(cantripHandle);
      const response = await record.crystal.query(
        [
          { role: "system", content: record.call },
          { role: "user", content: intent },
        ],
        null, // no tools
      );
      return truncateResult(completionText(response));
    }

    // ── Full cantrip: entity loop with medium, gates, wards ──
    if (progress) {
      progress({ type: "sub_entity_start", depth: 1, query: intent });
    }

    const child = cantrip({
      crystal: record.crystal,
      call: record.call,
      circle: record.circle,
      loom: sharedLoom,
      dependency_overrides: config.dependency_overrides,
    });

    try {
      const result = await child.cast(intent);
      const output = typeof result === "string" ? result : String(result);
      return truncateResult(output);
    } finally {
      if (progress) {
        progress({ type: "sub_entity_end", depth: 1 });
      }
      // cantrip.cast() already disposes the circle, so just remove the handle.
      handles.remove(cantripHandle);
    }
  },
  { dependencies: { handles: handlesDep, loom: loomDep, config: configDep, onProgress: progressBinding } },
);
cantripCastGate.docs = {
  sandbox_name: "cast",
  signature: "cast(cantrip_handle, intent: string): string",
  description: "Cast a cantrip. Full: runs entity loop, returns answer. Leaf: single LLM call. Handle is consumed.",
  section: SECTION,
};

/**
 * dispose(cantrip) — manually dispose a cantrip that was never cast.
 *
 * If you create a cantrip but decide not to cast it, call dispose() to
 * clean up any allocated resources (medium, circle). Cast auto-disposes,
 * so you only need this for cantrips you abandon.
 */
const cantripDisposeGate = rawGate<{ cantrip: number }>(
  {
    name: "cantrip_dispose",
    description: "Dispose an un-cast cantrip to free its resources.",
    parameters: {
      type: "object",
      properties: {
        cantrip: { type: "integer", description: "Cantrip handle to dispose." },
      },
      required: ["cantrip"],
      additionalProperties: false,
    },
  },
  async ({ cantrip: cantripHandle }, deps) => {
    const handles = deps.handles as CantripHandleStore;
    const record = handles.remove(cantripHandle);
    if (record.kind === "full" && record.circle.dispose) {
      await record.circle.dispose();
    }
    return true;
  },
  { dependencies: { handles: handlesDep } },
);
cantripDisposeGate.docs = {
  sandbox_name: "dispose",
  signature: "dispose(cantrip_handle): void",
  description: "Dispose an un-cast cantrip to free its resources. Cast auto-disposes.",
  section: SECTION,
};

// ── Batch cast ──────────────────────────────────────────────────────

const MAX_BATCH_CONCURRENCY = 8;
const MAX_BATCH_SIZE = 50;

/**
 * cast_batch(tasks) — cast multiple cantrips in parallel.
 *
 * Takes an array of {cantrip, intent} pairs. Fires them concurrently on the
 * Node event loop (chunked at 8), returns an array of result strings.
 * Each handle is consumed, same as cast().
 *
 * Hand-built BoundGate (not rawGate) because we return a raw array that must
 * pass through to the sandbox without serializeBoundGate wrapping.
 */
function makeCastBatchGate(): BoundGate {
  const gate: BoundGate = {
    name: "cantrip_cast_batch",
    definition: {
      name: "cantrip_cast_batch",
      description:
        "Cast multiple cantrips in parallel. Returns an array of result strings.",
      parameters: {
        type: "object",
        properties: {
          tasks: {
            type: "array",
            items: {
              type: "object",
              properties: {
                cantrip: { type: "integer", description: "Cantrip handle." },
                intent: { type: "string", description: "Intent for this cantrip." },
              },
              required: ["cantrip", "intent"],
            },
            description: "Array of {cantrip, intent} objects (max 50).",
          },
        },
        required: ["tasks"],
        additionalProperties: false,
      },
    },
    ephemeral: false,
    docs: {
      sandbox_name: "cast_batch",
      signature: "cast_batch(tasks: [{cantrip, intent}, ...]): string[]",
      description:
        "Cast multiple cantrips in parallel. Returns array of results. Handles are consumed.",
      section: SECTION,
    },
    execute: async (args: Record<string, any>, overrides?: DependencyOverrides) => {
      const handles = await handlesDep.resolve(overrides);
      const sharedLoom: Loom | undefined = await loomDep.resolve(overrides);
      const config = await configDep.resolve(overrides);
      const progress: ProgressCallback | null = await progressBinding.resolve(overrides);

      const tasks = args.tasks;
      if (!Array.isArray(tasks)) {
        throw new Error("cast_batch(tasks) requires an array of task objects.");
      }
      if (tasks.length > MAX_BATCH_SIZE) {
        throw new Error(
          `cast_batch: array too large (${tasks.length} > ${MAX_BATCH_SIZE}). Split into smaller batches.`,
        );
      }

      if (progress) {
        progress({ type: "batch_start", depth: 1, count: tasks.length });
      }

      const results: string[] = [];

      for (let i = 0; i < tasks.length; i += MAX_BATCH_CONCURRENCY) {
        const chunk = tasks.slice(i, i + MAX_BATCH_CONCURRENCY);
        const chunkResults = await Promise.all(
          chunk.map(async (task: any, j: number) => {
            const idx = i + j;
            const cantripHandle = task.cantrip;
            const intent = task.intent;

            if (!intent || typeof intent !== "string") {
              throw new Error(`cast_batch: tasks[${idx}].intent must be a string`);
            }

            if (progress) {
              progress({
                type: "batch_item",
                depth: 1,
                index: idx,
                total: tasks.length,
                query: intent,
              });
            }

            const { record } = handles.get(cantripHandle);

            try {
              // ── Leaf cantrip ──
              if (record.kind === "leaf") {
                handles.remove(cantripHandle);
                const response = await record.crystal.query(
                  [
                    { role: "system", content: record.call },
                    { role: "user", content: intent },
                  ],
                  null,
                );
                return truncateResult(completionText(response));
              }

              // ── Full cantrip ──
              const child = cantrip({
                crystal: record.crystal,
                call: record.call,
                circle: record.circle,
                loom: sharedLoom,
                dependency_overrides: config.dependency_overrides,
              });

              const result = await child.cast(intent);
              const output = typeof result === "string" ? result : String(result);
              handles.remove(cantripHandle);
              return truncateResult(output);
            } catch (err: any) {
              // Don't kill the batch — return error as result string
              try { handles.remove(cantripHandle); } catch { /* already removed */ }
              return `Error: ${err?.message ?? String(err)}`;
            }
          }),
        );
        results.push(...chunkResults);
      }

      if (progress) {
        progress({ type: "batch_end", depth: 1 });
      }

      return results as any;
    },
  };

  return gate;
}

// ── Factory ──────────────────────────────────────────────────────────

/**
 * Create cantrip construction gates and their dependency overrides.
 *
 * Returns gates to spread into Circle({ gates: [...] }) and a dependency_overrides
 * map to pass to cantrip({ dependency_overrides: ... }).
 */
export function cantripGates(
  config: CantripMediumConfig,
  parentLoom?: Loom,
): { gates: BoundGate[]; overrides: Map<any, any> } {
  const handles = new CantripHandleStore();
  const sharedLoom = parentLoom ?? config.loom;

  const gates: BoundGate[] = [
    cantripCreateGate,
    cantripCastGate,
    makeCastBatchGate(),
    cantripDisposeGate,
  ];

  const overrides = new Map<any, any>([
    [getCantripHandleStore, () => handles],
    [getCantripConfig, () => config],
    [getCantripLoom, () => sharedLoom],
  ]);

  return { gates, overrides };
}
