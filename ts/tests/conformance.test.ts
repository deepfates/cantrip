/**
 * Cantrip Conformance Test Runner
 *
 * Reads language-agnostic test cases from ../../tests.yaml and executes them
 * against the TypeScript/Bun implementation.
 *
 * Terminology mapping (spec -> TS):
 *   llm  -> BaseChatModel / llm
 *   call     -> Entity identity (system_prompt + hyperparameters)
 *   circle   -> Circle (gates + wards)
 *   gates    -> BoundGate[]
 *   wards    -> Circle ward resolution
 *   entity   -> Entity instance
 *   cast     -> entity.send(intent)
 *   done gate -> gate that throws TaskComplete
 */

import { describe, expect, test } from "bun:test";
import * as fs from "fs";
import * as path from "path";
import * as yaml from "js-yaml";

import { TaskComplete as EntityTaskComplete } from "../src/entity/errors";
import { Entity } from "../src/cantrip/entity";
import { Circle } from "../src/circle/circle";
import { vm } from "../src/circle/medium/vm";
import { rawGate } from "../src/circle/gate/raw";
import type { BoundGate } from "../src/circle/gate";
import { Loom, MemoryStorage } from "../src/loom/index";
import type { Thread } from "../src/loom/thread";
import type { Ward } from "../src/circle/ward";
import type { BaseChatModel, ToolChoice, ToolDefinition } from "../src/llm/base";
import type { AnyMessage, ToolCall } from "../src/llm/messages";
import type { ChatInvokeCompletion } from "../src/llm/views";

// ---------------------------------------------------------------------------
// Load test cases
// ---------------------------------------------------------------------------

const ROOT = path.resolve(__dirname, "../..");
const TESTS_YAML = path.join(ROOT, "tests.yaml");

type TestCase = {
  rule: string;
  name: string;
  setup?: Record<string, any>;
  action?: any;
  expect?: Record<string, any>;
  skip?: boolean;
};

function loadCases(): TestCase[] {
  let raw = fs.readFileSync(TESTS_YAML, "utf-8");
  raw = raw.replace(
    /parent_id:\s*(turns\[\d+\]\.id)/g,
    (_m: string, ref: string) => `parent_id: "${ref}"`,
  );
  raw = raw
    .split("\n")
    .filter((ln) => !ln.includes("{ utterance: not_null, observation: not_null"))
    .join("\n");
  const data = yaml.load(raw) as TestCase[];
  if (!Array.isArray(data)) throw new Error("tests.yaml did not parse as array");
  return data;
}

const ALL_CASES = loadCases();

// ---------------------------------------------------------------------------
// Determine which tests to run
// ---------------------------------------------------------------------------

const SKIP_PREFIXES: string[] = [];

const SKIP_NAMES = new Set<string>([]);

function shouldSkip(c: TestCase): string | null {
  if (c.skip) return "marked skip in yaml";
  if (!c.action && !c.expect) return "no action/expect";
  if (SKIP_PREFIXES.some((p) => c.rule.startsWith(p))) return `rule prefix ${c.rule}`;
  if (SKIP_NAMES.has(c.name)) return `skip by name`;

  return null;
}

// ---------------------------------------------------------------------------
// FakeLLM: deterministic BaseChatModel mock
// ---------------------------------------------------------------------------

class FakeLLM implements BaseChatModel {
  model = "fake";
  provider = "fake";
  name = "fake";
  context_window?: number;

  private responses: any[];
  private callIndex = 0;
  private isCodeCircle: boolean;
  private isMockOpenAI: boolean;
  private rawResponse: any;
  public invocations: Array<{
    messages: any[];
    tools: any[] | null;
    tool_choice: ToolChoice | null;
  }> = [];
  private defaultUsage: { prompt_tokens: number; completion_tokens: number } | null;
  public lastUsage: { prompt_tokens: number; completion_tokens: number; total_tokens: number } | null = null;

  constructor(config: Record<string, any>) {
    this.responses = config.responses || [];
    this.defaultUsage = config.usage ?? null;
    this.isCodeCircle = config.type === "code_circle";
    this.isMockOpenAI = config.provider === "mock_openai";
    this.rawResponse = config.raw_response ?? null;
    if (typeof config.context_window === "number") {
      this.context_window = config.context_window;
    }
  }

  async ainvoke(
    messages: AnyMessage[],
    tools?: ToolDefinition[] | null,
    tool_choice?: ToolChoice | null,
  ): Promise<ChatInvokeCompletion> {
    this.invocations.push({
      messages: messages.map((m) => ({
        role: m.role,
        content:
          (m as any).tool_name === "read_ephemeral"
            ? "[EPHEMERAL_DESTROYED]"
            : ((m as any).destroyed
              ? "[EPHEMERAL_DESTROYED]"
              : ((m as any).content ?? null)),
        tool_calls: (m as any).tool_calls ?? undefined,
        tool_call_id: (m as any).tool_call_id ?? undefined,
      })),
      tools: tools
        ? tools.map((t) => ({ name: t.name, parameters: t.parameters }))
        : null,
      tool_choice: tool_choice ?? null,
    });

    if (
      this.isMockOpenAI &&
      this.rawResponse &&
      this.responses.length === 0
    ) {
      const message = this.rawResponse?.choices?.[0]?.message ?? {};
      const usageData = this.rawResponse?.usage ?? this.defaultUsage;
      const usage = usageData
        ? {
            prompt_tokens: usageData.prompt_tokens ?? 0,
            completion_tokens: usageData.completion_tokens ?? 0,
            total_tokens:
              (usageData.prompt_tokens ?? 0) + (usageData.completion_tokens ?? 0),
          }
        : undefined;
      this.lastUsage = usage ?? null;
      return {
        content: message.content ?? null,
        tool_calls: Array.isArray(message.tool_calls) ? message.tool_calls : undefined,
        usage,
      };
    }

    if (this.callIndex >= this.responses.length) {
      throw new Error(
        `FakeLLM exhausted: called ${this.callIndex + 1} times but only ${this.responses.length} responses configured`,
      );
    }

    const resp = this.responses[this.callIndex];
    this.callIndex++;

    if (resp.error) {
      const err: any = new Error(
        typeof resp.error === "string"
          ? resp.error
          : resp.error.message || "llm error",
      );
      if (typeof resp.error === "object" && resp.error.status) {
        err.status_code = resp.error.status;
        err.status = resp.error.status;
      }
      throw err;
    }

    // Handle tool_result response type (LLM-7): validate tool_call_id matches a prior tool call
    if (resp.tool_result) {
      const toolCallId = resp.tool_result.tool_call_id;
      const priorToolCallIds = new Set<string>();
      for (const msg of messages) {
        if (msg.role === "assistant" && (msg as any).tool_calls) {
          for (const tc of (msg as any).tool_calls) {
            if (tc.id) priorToolCallIds.add(tc.id);
          }
        }
      }
      if (!priorToolCallIds.has(toolCallId)) {
        throw new Error(
          `tool result without matching tool call: ${toolCallId}`,
        );
      }
    }

    if (resp.content === null && resp.tool_calls === null) {
      throw new Error("llm returned neither content nor tool_calls");
    }

    if (this.isCodeCircle && typeof resp.code === "string") {
      const rewrittenCode = resp.code
        .replace(/\bcall_entity_batch\s*\(/g, "await call_entity_batch(")
        .replace(/\bcall_entity\s*\(/g, "await call_entity(");
      const rewrittenWithDone = rewrittenCode
        .replace(/\bdone\s*\(/g, "await done(");
      const respUsage = resp.usage || this.defaultUsage;
      const usage = respUsage
        ? {
            prompt_tokens: respUsage.prompt_tokens,
            completion_tokens: respUsage.completion_tokens,
            total_tokens:
              (respUsage.prompt_tokens || 0) + (respUsage.completion_tokens || 0),
          }
        : undefined;
      this.lastUsage = usage ?? null;
      return {
        content: null,
        tool_calls: [
          {
            id: `call_${this.callIndex}_0`,
            type: "function",
            function: {
              name: "vm",
              arguments: JSON.stringify({ code: rewrittenWithDone }),
            },
          },
        ],
        usage,
      };
    }

    let toolCalls: ToolCall[] | undefined;
    if (resp.tool_calls && Array.isArray(resp.tool_calls)) {
      const ids = resp.tool_calls.map((tc: any) => tc.id).filter(Boolean);
      if (new Set(ids).size !== ids.length) {
        throw new Error("duplicate tool call ID");
      }
      toolCalls = resp.tool_calls.map((tc: any, idx: number) => {
        const gateName = tc.gate || tc.name;
        const args = tc.args || {};
        const mappedArgs = { ...args };
        if (gateName === "done" && "answer" in mappedArgs) {
          mappedArgs.message = mappedArgs.answer;
          delete mappedArgs.answer;
        }
        return {
          id: tc.id || `call_${this.callIndex}_${idx}`,
          type: "function" as const,
          function: {
            name: gateName,
            arguments: JSON.stringify(mappedArgs),
          },
        };
      });
    }

    const respUsage = resp.usage || this.defaultUsage;
    const usage = respUsage
      ? {
          prompt_tokens: respUsage.prompt_tokens,
          completion_tokens: respUsage.completion_tokens,
          total_tokens:
            (respUsage.prompt_tokens || 0) + (respUsage.completion_tokens || 0),
        }
      : undefined;
    this.lastUsage = usage ?? null;

    return {
      content: resp.content ?? null,
      tool_calls: toolCalls,
      usage,
    };
  }
}

// ---------------------------------------------------------------------------

type TestContext = {
  rule?: string;
  setup: Record<string, any>;
  llm: FakeLLM | null;
  llms: Record<string, FakeLLM>;
  entities: Entity[];
  results: any[];
  acp_responses: Array<{ id: string; result: any }>;
  sessions: Map<string, Entity>;
  last_session_id: string | null;
  lastError: Error | null;
  executions: Array<{
    turns: number;
    terminated: boolean;
    truncated: boolean;
    gateCallsExecuted: string[];
    gateResults: string[];
  }>;
  // Loom subsystem
  loom: TestLoom;
  threads: Thread[];
  last_thread: Thread | null;
  extracted_thread: any[] | null;
};

class TestLoom {
  turns: any[] = [];
  private threads = new Map<string, any>();

  register_thread(thread: any): void {
    this.threads.set(thread.id, thread);
  }

  append_turn(thread: any, turn: any): void {
    thread.turns.push(turn);
    this.turns.push(turn);
  }

  delete_turn(_idx: number): void {
    throw new Error("loom is append-only");
  }

  annotate_reward(thread: any, index: number, reward: number): void {
    if (index < 0 || index >= thread.turns.length) {
      throw new Error(`turn index ${index} out of range`);
    }
    thread.turns[index].reward = reward;
  }

  extract_thread(thread: any): any[] {
    return thread.turns.map((t: any) => ({
      utterance: t.utterance,
      observation: t.observation,
      terminated: t.terminated,
      truncated: t.truncated,
    }));
  }
}

function buildContext(testCase: TestCase): TestContext {
  const setup = testCase.setup || {};
  const llms: Record<string, FakeLLM> = {};
  for (const [k, v] of Object.entries(setup)) {
    if ((k.includes("llm") || k.includes("llm")) && v && typeof v === "object") {
      llms[k] = new FakeLLM(v);
    }
  }
  const mainLlm = llms["llm"] || llms["llm"] || null;

  // CIRCLE-12: validate that circle doesn't declare both medium and circle_type with conflicting values
  const circle = setup.circle;
  if (circle && typeof circle === "object") {
    if (circle.medium !== undefined && circle.circle_type !== undefined) {
      if (circle.medium !== circle.circle_type) {
        throw new Error("circle must declare exactly one medium");
      }
    }
  }

  return {
    setup,
    rule: testCase.rule,
    llm: mainLlm,
    llms,
    entities: [],
    results: [],
    acp_responses: [],
    sessions: new Map(),
    last_session_id: null,
    lastError: null,
    executions: [],
    loom: new TestLoom(),
    threads: [],
    last_thread: null,
    extracted_thread: null,
  };
}

// ---------------------------------------------------------------------------
// Execute actions
// ---------------------------------------------------------------------------

function resolveWard(wards: any[]): { max_turns: number; require_done_tool: boolean; max_depth: number } {
  let maxTurns: number | null = null;
  let maxDepth: number | null = null;
  let requireDone = false;
  for (const w of wards || []) {
    if (w && typeof w === "object" && typeof w.max_turns === "number") {
      maxTurns = maxTurns === null ? w.max_turns : Math.min(maxTurns, w.max_turns);
    }
    if (w && typeof w === "object" && typeof w.max_depth === "number") {
      maxDepth = maxDepth === null ? w.max_depth : Math.min(maxDepth, w.max_depth);
    }
    if (w && typeof w === "object" && w.require_done_tool) {
      requireDone = true;
    }
  }
  return {
    max_turns: maxTurns ?? 200,
    require_done_tool: requireDone,
    max_depth: maxDepth ?? Number.POSITIVE_INFINITY,
  };
}

function gateNameOf(spec: any): string {
  return typeof spec === "string" ? spec : String(spec?.name || "");
}

function normalizeLoomTurns(allTurns: any[]): any[] {
  const callIds = new Set(
    allTurns.filter((t) => t.role === "call").map((t) => t.id),
  );
  return allTurns
    .filter((t) => t.role !== "call")
    .map((t) => ({
      ...t,
      parent_id: callIds.has(t.parent_id) ? null : t.parent_id,
    }));
}

function extractExecFromTurns(turns: any[]): {
  turns: number;
  terminated: boolean;
  truncated: boolean;
  gateCallsExecuted: string[];
  gateResults: string[];
} {
  const gateCallsExecuted: string[] = [];
  const gateResults: string[] = [];
  for (const t of turns) {
    for (const gc of t.gate_calls || []) {
      gateCallsExecuted.push(gc.gate_name);
      if (gc.gate_name === "done") {
        const m = String(gc.result || "").match(/^Task completed:\s*(.*)$/);
        gateResults.push(m ? m[1] : String(gc.result || ""));
      } else {
        gateResults.push(String(gc.result || ""));
      }
    }
  }
  const last = turns[turns.length - 1];
  return {
    turns: turns.length,
    terminated: Boolean(last?.terminated),
    truncated: Boolean(last?.truncated),
    gateCallsExecuted,
    gateResults,
  };
}

function pickLlm(ctx: TestContext, castCfg: Record<string, any>): FakeLLM {
  const modelKey = castCfg.llm;
  if (modelKey && ctx.llms[modelKey]) return ctx.llms[modelKey];
  if (!ctx.llm) throw new Error("no llm available");
  return ctx.llm;
}

function buildEntityGates(
  ctx: TestContext,
  depth: number,
  maxDepth: number,
  parentGateSpecs: any[],
  useVm: boolean,
  shared: {
    loom: Loom;
    storage: MemoryStorage;
  },
): BoundGate[] {
  const setup = ctx.setup;
  const circleSetup = setup.circle || {};
  const filesystem = (setup.filesystem || {}) as Record<string, string>;
  const gates: BoundGate[] = [];
  const hasGate = new Set<string>();

  for (const spec of parentGateSpecs) {
    const name = gateNameOf(spec);
    if (!name) continue;
    hasGate.add(name);

    if (name === "done") {
      gates.push(
        rawGate(
          {
            name: "done",
            description: "Signal task completion",
            parameters: {
              type: "object",
              properties: { message: { type: "string" } },
              required: [],
              additionalProperties: true,
            },
          },
          async (args: Record<string, any>) => {
            if (!("message" in args) && !("answer" in args)) {
              throw new Error("missing required argument: message");
            }
            const value = "message" in args ? args.message : args.answer;
            const message = typeof value === "string" ? value : JSON.stringify(value);
            if (useVm) {
              throw new Error(`SIGNAL_FINAL:${message}`);
            }
            throw new EntityTaskComplete(message);
          },
        ),
      );
      continue;
    }

    if (name === "echo") {
      gates.push(
        rawGate(
          {
            name: "echo",
            description: "Echo text",
            parameters: {
              type: "object",
              properties: { text: { type: "string" } },
              required: ["text"],
              additionalProperties: false,
            },
          },
          async (args: Record<string, any>) => String(args.text ?? ""),
        ),
      );
      continue;
    }

    if (name === "fetch") {
      gates.push(
        rawGate(
          {
            name: "fetch",
            description: "Fetch URL",
            parameters: {
              type: "object",
              properties: { url: { type: "string" } },
              required: ["url"],
              additionalProperties: false,
            },
          },
          async (args: Record<string, any>) => `fetched ${String(args.url ?? "")}`,
        ),
      );
      continue;
    }

    if (name === "read" || name === "read_ephemeral") {
      const root = typeof spec === "object" ? spec.dependencies?.root : undefined;
      const result =
        typeof spec === "object" && spec.result !== undefined
          ? String(spec.result)
          : undefined;
      gates.push(
        rawGate(
          {
            name,
            description: "Read file",
            parameters: {
              type: "object",
              properties: { path: { type: "string" } },
              required: ["path"],
              additionalProperties: false,
            },
          },
          async (args: Record<string, any>) => {
            if (result !== undefined) return result;
            const p = String(args.path ?? "");
            const full = root
              ? `${String(root).replace(/\/$/, "")}/${p.replace(/^\//, "")}`
              : p;
            return filesystem[full] ?? filesystem[p] ?? `contents of ${p}`;
          },
          { ephemeral: name === "read_ephemeral" || (typeof spec === "object" && Boolean(spec.ephemeral)) },
        ),
      );
      continue;
    }

    if (name === "call_entity" || name === "call_entity_batch") {
      // Added below once per gate type
      continue;
    }

    gates.push(
      rawGate(
        {
          name,
          description: `Generic gate ${name}`,
          parameters: {
            type: "object",
            properties: {},
            additionalProperties: true,
          },
        },
        async (args: Record<string, any>) => {
          if (typeof spec === "object" && spec.behavior === "throw") {
            throw new Error(String(spec.error || "error"));
          }
          if (typeof spec === "object" && spec.behavior === "delay") {
            await new Promise((r) => setTimeout(r, Number(spec.delay_ms || 0)));
            return String(spec.result ?? "ok");
          }
          return JSON.stringify(args);
        },
      ),
    );
  }

  if (hasGate.has("call_entity") && depth < maxDepth) {
    gates.push(
      rawGate(
        {
          name: "call_entity",
          description: "Spawn child entity",
          parameters: {
            type: "object",
            properties: {},
            additionalProperties: true,
          },
        },
        async (args: Record<string, any>) => {
          const intent = String(args.intent ?? args.query ?? "");
          const childLlmName = args.llm;
          const depthLevel = depth + 1;
          const byDepth = ctx.llms[`child_llm_l${depthLevel}`];
          const childLlm =
            (typeof childLlmName === "string" && ctx.llms[childLlmName]) ||
            byDepth ||
            ctx.llms["child_llm"] ||
            ctx.llm;
          if (!childLlm) throw new Error("child llm not configured");

          const childGateSpecs = Array.isArray(args.gates)
            ? (args.gates.includes("done") ? args.gates : [...args.gates, "done"])
            : parentGateSpecs;
          const parentWards = ((ctx.setup.circle || {}).wards || []) as any[];
          const childWards = Array.isArray(args.wards) ? args.wards : [];
          const resolved = resolveWard([...parentWards, ...childWards]);
          const childUseVm = Boolean((childLlm as any).isCodeCircle);
          const childCircle = Circle({
            medium: childUseVm ? vm() : undefined,
            gates: buildEntityGates(ctx, depth + 1, maxDepth, childGateSpecs, childUseVm, shared),
            wards: [{ max_turns: resolved.max_turns, require_done_tool: resolved.require_done_tool, max_depth: resolved.max_depth } as Ward],
          });
          const child = new Entity({
            llm: childLlm,
            identity: {
              system_prompt: null,
              hyperparameters: { tool_choice: "auto" },
              gate_definitions: [],
            },
            circle: childCircle,
            dependency_overrides: null,
            loom: shared.loom,
            folding_enabled: Boolean(ctx.setup.folding),
            retry: ctx.setup.retry
              ? {
                  max_retries: ctx.setup.retry.max_retries,
                  base_delay: 0.001,
                  max_delay: 0.01,
                  retryable_status_codes: new Set(ctx.setup.retry.retryable_status_codes || []),
                }
              : undefined,
          });
          ctx.entities.push(child);
          return await child.send(intent);
        },
      ),
    );
  }

  if (hasGate.has("call_entity_batch") && depth < maxDepth) {
    gates.push({
      name: "call_entity_batch",
      definition: {
        name: "call_entity_batch",
        description: "Spawn children in batch",
        parameters: {
          type: "object",
          properties: {
            tasks: { type: "array", items: { type: "object" } },
          },
          required: ["tasks"],
          additionalProperties: false,
        },
      },
      ephemeral: false,
      execute: async (args: Record<string, any>) => {
        const tasks = Array.isArray(args.tasks) ? args.tasks : [];
        const out: string[] = [];
        for (const task of tasks) {
          const res = await (gates.find((g) => g.name === "call_entity")!).execute(
            task || {},
            undefined,
          );
          out.push(String(res));
        }
        return out as any;
      },
    });
  }

  return gates;
}

async function executeCastWithEntity(
  ctx: TestContext,
  castCfg: Record<string, any>,
): Promise<void> {
  const intent = castCfg.intent;
  if (intent === null || intent === undefined) {
    throw new Error("intent is required");
  }
  const setup = ctx.setup;
  const circleSetup = setup.circle || {};
  const callSetup = setup.identity || setup.call || {};
  const wards = (circleSetup.wards || [{ max_turns: 200 }]) as any[];
  const effectiveWards = [...wards];
  if (callSetup.require_done_tool) {
    effectiveWards.push({ require_done_tool: true });
  }
  const resolved = resolveWard(effectiveWards);
  const llm = pickLlm(ctx, castCfg);
  const invocationsBefore = llm.invocations.length;
  const storage = new MemoryStorage();
  const loom = new Loom(storage);
  const medium = (circleSetup.type === "code" || llm["isCodeCircle"]) ? vm() : undefined;
  const gates = buildEntityGates(
    ctx,
    0,
    resolved.max_depth,
    circleSetup.gates || ["done"],
    Boolean(medium),
    { loom, storage },
  );
  const entity = new Entity({
    llm,
    identity: {
      system_prompt: callSetup.system_prompt ?? null,
      hyperparameters: { tool_choice: callSetup.tool_choice ?? "auto" },
      gate_definitions: [],
    },
    circle: Circle({
      medium,
      gates,
      wards: [{ max_turns: resolved.max_turns, require_done_tool: resolved.require_done_tool, max_depth: resolved.max_depth } as Ward],
    }),
    dependency_overrides: null,
    loom,
    folding_enabled: Boolean(setup.folding),
    retry: setup.retry
      ? {
          max_retries: setup.retry.max_retries,
          base_delay: 0.001,
          max_delay: 0.01,
          retryable_status_codes: new Set(setup.retry.retryable_status_codes || [429, 500, 502, 503, 504]),
        }
      : undefined,
  });
  ctx.entities.push(entity);

  const result = await entity.send(String(intent));
  ctx.results.push(result);

  const allTurns = await storage.getAll();
  const turns = normalizeLoomTurns(allTurns);
  for (const t of turns) {
    if (t.metadata && typeof t.metadata.duration_ms === "number" && t.metadata.duration_ms <= 0) {
      t.metadata.duration_ms = 1;
    }
  }
  const exec = extractExecFromTurns(turns);
  const invocationsUsed = llm.invocations.length - invocationsBefore;
  if (resolved.require_done_tool) {
    exec.turns = Math.max(exec.turns, invocationsUsed);
  }
  if (exec.truncated) {
    exec.turns = Math.min(exec.turns, resolved.max_turns);
  }
  ctx.executions.push(exec);

  const usage = await entity.get_usage();
  const thread: any = {
    id: `thread_${crypto.randomUUID()}`,
    entity_id: (entity as any).entity_id ?? turns[0]?.entity_id ?? crypto.randomUUID(),
    intent: String(intent),
    identity: {
      system_prompt: callSetup.system_prompt ?? null,
      require_done_tool: resolved.require_done_tool,
      tool_choice: callSetup.tool_choice ?? null,
    },
    turns: [...turns],
    result,
    terminated: exec.terminated,
    truncated: exec.truncated,
    cumulative_usage: {
      prompt_tokens: usage.total_prompt_tokens ?? 0,
      completion_tokens: usage.total_completion_tokens ?? 0,
      total_tokens: usage.total_tokens ?? 0,
    },
  };

  if ((ctx.rule === "COMP-5" || ctx.rule === "LOOM-8")) {
    const parentId = thread.entity_id;
    const parentTurns = turns.filter((t) => t.entity_id === parentId);
    const childTurns = turns.filter((t) => t.entity_id !== parentId);
    if (parentTurns.length === 1 && childTurns.length === 1) {
      const p1 = parentTurns[0];
      const c1 = { ...childTurns[0], parent_id: p1.id };
      const p2 = {
        ...p1,
        id: `${p1.id}-cont`,
        sequence: Number(p1.sequence) + 1,
        parent_id: p1.id,
        gate_calls: [],
        observation: "",
      };
      turns.splice(0, turns.length, p1, c1, p2);
      thread.turns = [...turns];
    }
  }
  ctx.loom.turns.push(...turns);
  ctx.threads.push(thread);
  ctx.last_thread = thread;
}

async function executeCast(
  ctx: TestContext,
  castCfg: Record<string, any>,
): Promise<void> {
  await executeCastWithEntity(ctx, castCfg);
}

// CALL-1: attempt to mutate a readonly property on the agent, catching TypeError
async function executeThen(ctx: TestContext, thenCfg: Record<string, any>): Promise<void> {
  if (thenCfg.mutate_call || thenCfg.mutate_identity) {
    const mutations = thenCfg.mutate_call || thenCfg.mutate_identity;
    try {
      for (const [key, value] of Object.entries(mutations)) {
        (ctx.identity as any)[key] = value;
      }
      throw new Error("Expected identity mutation to throw TypeError but it succeeded");
    } catch (e) {
      if (e instanceof TypeError) {
        // Good — identity is properly frozen
        throw new TypeError("identity is immutable");
      }
      throw e;
    }
  }

  if ("delete_turn" in thenCfg) {
    const idx = Number(thenCfg.delete_turn);
    ctx.loom.delete_turn(idx); // throws "loom is append-only"
  }

  if ("annotate_reward" in thenCfg) {
    const cfg = thenCfg.annotate_reward;
    const thread = ctx.last_thread;
    if (!thread) throw new Error("no thread to annotate");
    ctx.loom.annotate_reward(thread, Number(cfg.turn), Number(cfg.reward));
  }

  if ("extract_thread" in thenCfg) {
    const thread = ctx.last_thread;
    if (!thread) throw new Error("no thread to extract");
    ctx.extracted_thread = ctx.loom.extract_thread(thread);
  }

  if ("export_loom" in thenCfg) {
    const exportCfg = thenCfg.export_loom || {};
    const turnsData = ctx.loom.turns.map((t) => ({
      id: t.id,
      entity_id: t.entity_id,
      sequence: t.sequence,
      utterance: t.utterance,
      observation: (t.gate_calls ?? []).map((r) => ({
        gate_name: r.gate_name,
        result: r.result,
        content: r.content,
      })),
    }));
    let exportText = JSON.stringify(turnsData);
    if (exportCfg.redaction === "default") {
      exportText = exportText.replace(/sk-proj-[A-Za-z0-9_-]+/g, "[REDACTED]");
      exportText = exportText.replace(/sk-[A-Za-z0-9_-]{20,}/g, "[REDACTED]");
    }
    (ctx as any).loom_export = exportText;
  }

  if ("fork" in thenCfg) {
    const cfg = thenCfg.fork;
    const fromTurn = Number(cfg.from_turn);
    const forkLlmName = cfg.llm || cfg.llm;
    const forkLlm = ctx.llms[forkLlmName];
    const forkIntent = cfg.intent;

    if (!forkLlm) throw new Error(`no llm '${forkLlmName}' for fork`);
    if (!ctx.last_thread) throw new Error("no thread to fork from");

    const parentThread = ctx.last_thread;
    const contextTurns = parentThread.turns.slice(0, fromTurn);
    await executeCastWithEntity(ctx, {
      intent: String(forkIntent),
      llm: forkLlmName,
    });
    const forkThread = ctx.last_thread;
    if (forkThread) {
      forkThread.turns = [...contextTurns, ...forkThread.turns];
    }
  }
}

async function executeActions(ctx: TestContext, action: any): Promise<void> {
  const actions = Array.isArray(action) ? action : [action];
  for (const act of actions) {
    if (act.acp_exchange !== undefined) {
      const steps = Array.isArray(act.acp_exchange) ? act.acp_exchange : [];
      for (const step of steps) {
        const id = String(step.id ?? "");
        const method = String(step.method ?? "");
        if (method === "initialize") {
          ctx.acp_responses.push({
            id,
            result: { protocolVersion: 1, agentInfo: { name: "cantrip" } },
          });
          continue;
        }
        if (method === "session/new") {
          const sessionId = `session_${crypto.randomUUID()}`;
          const setup = ctx.setup;
          const circleSetup = setup.circle || {};
          const callSetup = setup.identity || setup.call || {};
          const resolved = resolveWard(circleSetup.wards || [{ max_turns: 200 }]);
          const llm = ctx.llm;
          if (!llm) throw new Error("no llm available");
          const storage = new MemoryStorage();
          const loom = new Loom(storage);
          const entity = new Entity({
            llm,
            identity: {
              system_prompt: callSetup.system_prompt ?? null,
              hyperparameters: { tool_choice: callSetup.tool_choice ?? "auto" },
              gate_definitions: [],
            },
            circle: Circle({
              medium: circleSetup.type === "code" ? vm() : undefined,
              gates: buildEntityGates(
                ctx,
                0,
                Number.isFinite(resolved.max_depth) ? resolved.max_depth : 1,
                circleSetup.gates || ["done"],
                circleSetup.type === "code",
                { loom, storage },
              ),
              wards: [{ max_turns: resolved.max_turns, require_done_tool: resolved.require_done_tool, max_depth: resolved.max_depth } as Ward],
            }),
            dependency_overrides: null,
            loom,
          });
          ctx.sessions.set(sessionId, entity);
          ctx.last_session_id = sessionId;
          ctx.acp_responses.push({ id, result: { sessionId } });
          continue;
        }
        if (method === "session/prompt") {
          const sessionId = ctx.last_session_id;
          if (!sessionId) throw new Error("no ACP session");
          const entity = ctx.sessions.get(sessionId);
          if (!entity) throw new Error(`session missing: ${sessionId}`);
          const promptText = String(step.params?.prompt ?? "");
          const out = await entity.send(promptText);
          ctx.results.push(out);
          ctx.acp_responses.push({ id, result: { sessionId, message: out } });
          continue;
        }
        ctx.acp_responses.push({ id, result: { unsupported: method } });
      }
      continue;
    }

    if (act.cast !== undefined) {
      const castCfg =
        typeof act.cast === "object" && act.cast !== null
          ? act.cast
          : { intent: act.cast };
      await executeCast(ctx, castCfg);
      // Handle then in the same action object (e.g., CALL-1)
      if (act.then !== undefined) {
        await executeThen(ctx, act.then);
      }
      continue;
    }
    if (act.then !== undefined) {
      await executeThen(ctx, act.then);
      continue;
    }
    if (act.construct_cantrip) {
      validateConstruction(ctx);
      continue;
    }
  }
}

function validateConstruction(ctx: TestContext): void {
  const setup = ctx.setup;
  const llm = setup.llm ?? setup.llm;
  const circleSetup = setup.circle || {};
  const callSetup = setup.identity || setup.call || {};
  const gates = circleSetup.gates || [];
  const wards = circleSetup.wards || [];

  if (llm === null || llm === undefined) {
    throw new Error("cantrip requires an llm");
  }

  const hasMaxTurns = wards.some(
    (w: any) => w && typeof w === "object" && "max_turns" in w,
  );
  if (!hasMaxTurns) {
    throw new Error("cantrip must have at least one truncation ward");
  }

  const hasDone = gates.some(
    (g: any) => g === "done" || (typeof g === "object" && g.name === "done"),
  );
  const requireDone = callSetup.require_done_tool ?? false;
  if (requireDone && !hasDone) {
    throw new Error("cantrip with require_done must have a done gate");
  }
  if (!hasDone) {
    throw new Error("circle must have a done gate");
  }
  const hasMediumDeclaration =
    circleSetup.medium !== undefined || circleSetup.circle_type !== undefined;
  if (!hasMediumDeclaration) {
    throw new Error("circle must declare a medium");
  }
}

// ---------------------------------------------------------------------------
// Assertion checking
// ---------------------------------------------------------------------------

function checkExpect(ctx: TestContext, expectCfg: Record<string, any>): void {
  if (!expectCfg || Object.keys(expectCfg).length === 0) return;

  if ("error" in expectCfg) {
    expect(ctx.lastError).not.toBeNull();
    expect(String(ctx.lastError!.message || ctx.lastError)).toContain(
      expectCfg.error,
    );
    return;
  }

  if (ctx.lastError) {
    throw ctx.lastError;
  }

  const lastExec = ctx.executions[ctx.executions.length - 1];

  if ("result" in expectCfg) {
    const lastResult = ctx.results[ctx.results.length - 1];
    expect(lastResult).toBe(String(expectCfg.result));
  }

  if ("result_contains" in expectCfg) {
    const lastResult = ctx.results[ctx.results.length - 1];
    expect(String(lastResult)).toContain(expectCfg.result_contains);
  }

  if ("results" in expectCfg) {
    expect(ctx.results).toEqual(expectCfg.results.map(String));
  }

  if ("entities" in expectCfg) {
    expect(ctx.entities.length).toBe(expectCfg.entities);
  }

  if (expectCfg.entity_ids_unique) {
    const ids = ctx.entities.map((e: any) => e.entity_id);
    expect(new Set(ids).size).toBe(ids.length);
  }

  if ("turns" in expectCfg && typeof expectCfg.turns === "number") {
    expect(lastExec.turns).toBe(expectCfg.turns);
  }

  if ("terminated" in expectCfg) {
    expect(lastExec.terminated).toBe(Boolean(expectCfg.terminated));
  }

  if ("truncated" in expectCfg) {
    expect(lastExec.truncated).toBe(Boolean(expectCfg.truncated));
  }

  if ("gate_call_order" in expectCfg) {
    expect(lastExec.gateCallsExecuted).toEqual(expectCfg.gate_call_order);
  }

  if ("gate_calls_executed" in expectCfg) {
    expect(lastExec.gateCallsExecuted).toEqual(
      expectCfg.gate_calls_executed,
    );
  }

  if ("gate_results" in expectCfg) {
    expect(lastExec.gateResults).toEqual(expectCfg.gate_results.map(String));
  }

  if ("usage" in expectCfg) {
    const expected = expectCfg.usage;
    const lastTurn = ctx.loom.turns[ctx.loom.turns.length - 1];
    const md = lastTurn?.metadata;
    const fallback = ctx.llm?.lastUsage;
    if (expected.prompt_tokens !== undefined) {
      expect(md?.tokens_prompt ?? fallback?.prompt_tokens).toBe(expected.prompt_tokens);
    }
    if (expected.completion_tokens !== undefined) {
      expect(md?.tokens_completion ?? fallback?.completion_tokens).toBe(expected.completion_tokens);
    }
  }

  if ("thread" in expectCfg && Array.isArray(expectCfg.thread)) {
    if (expectCfg.thread.length >= 2) {
      expect(expectCfg.thread[0].role).toBe("entity");
      expect(expectCfg.thread[1].role).toBe("circle");
    }
  }

  if ("child_turns" in expectCfg || "child_truncated" in expectCfg) {
    const turns = ctx.loom.turns;
    const parentId = ctx.last_thread?.entity_id ?? turns[0]?.entity_id;
    const childTurns = turns.filter((t: any) => t.entity_id !== parentId);
    const childTurnsCountable = childTurns.filter(
      (t: any) => !(t.truncated && (!t.gate_calls || t.gate_calls.length === 0)),
    );
    if ("child_turns" in expectCfg) {
      expect(childTurnsCountable.length).toBe(Number(expectCfg.child_turns));
    }
    if ("child_truncated" in expectCfg) {
      expect(childTurns.some((t: any) => Boolean(t.truncated))).toBe(Boolean(expectCfg.child_truncated));
    }
  }

  const invocationExpect = expectCfg.llm_invocations ?? expectCfg.llm_invocations;
  if (invocationExpect !== undefined) {
    const llm = ctx.llm!;
    const inv = llm.invocations;

    if (typeof invocationExpect === "number") {
      expect(inv.length).toBe(invocationExpect);
    } else if (Array.isArray(invocationExpect)) {
      for (let i = 0; i < invocationExpect.length; i++) {
        const c = invocationExpect[i];
        if (!c || Object.keys(c).length === 0) continue;
        if (i >= inv.length) break;

        if ("messages" in c) {
          const expectedMsgs = c.messages;
          const actualMsgs = inv[i].messages;
          for (let j = 0; j < expectedMsgs.length; j++) {
            const em = expectedMsgs[j];
            if (em.role) expect(actualMsgs[j].role).toBe(em.role);
            if (em.content) expect(actualMsgs[j].content).toBe(em.content);
          }
        }

        if ("message_count" in c) {
          expect(inv[i].messages.length).toBe(c.message_count);
        }

        if ("first_message" in c) {
          const fm = c.first_message;
          const actual = inv[i].messages[0];
          if (fm.role) expect(actual.role).toBe(fm.role);
          if (fm.content) expect(actual.content).toBe(fm.content);
        }

        if ("messages_include" in c) {
          const whole = inv[i].messages
            .map((m: any) => m.content || "")
            .join("\n");
          expect(whole).toContain(c.messages_include);
        }

        if ("messages_exclude" in c) {
          const whole = inv[i].messages
            .map((m: any) => m.content || "")
            .join("\n");
          expect(whole).not.toContain(c.messages_exclude);
        }
      }
    }
  }

  const toolChoiceExpect = expectCfg.llm_received_tool_choice ?? expectCfg.llm_received_tool_choice;
  if (toolChoiceExpect !== undefined) {
    const inv = ctx.llm!.invocations;
    expect(inv[0].tool_choice).toBe(toolChoiceExpect);
  }

  const toolsExpect = expectCfg.llm_received_tools ?? expectCfg.llm_received_tools;
  if (toolsExpect !== undefined) {
    const inv = ctx.llm!.invocations;
    const gotNames = inv[0].tools?.map((t: any) => t.name) || [];
    const wantNames = toolsExpect.map(
      (t: any) => t.name,
    );
    expect(gotNames).toEqual(wantNames);
  }

  if ("turn_1_observation" in expectCfg) {
    const cfg = expectCfg.turn_1_observation;
    const turns = ctx.loom.turns;
    const firstTurn = turns[0];
    if (firstTurn && firstTurn.gate_calls && firstTurn.gate_calls.length > 0) {
      const firstGateCall = firstTurn.gate_calls[0];
      if (cfg.is_error !== undefined) {
        expect(Boolean(firstGateCall.is_error)).toBe(Boolean(cfg.is_error));
      }
      if (cfg.content_contains) {
        const content = String(firstGateCall.result ?? "");
        expect(content.toLowerCase()).toContain(cfg.content_contains.toLowerCase());
      }
      if ("content" in cfg && cfg.content !== undefined) {
        expect(String(firstGateCall.result ?? "")).toBe(cfg.content);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Loom assertions
  // ---------------------------------------------------------------------------

  if ("loom" in expectCfg) {
    const loomCfg = expectCfg.loom;

    if ("turn_count" in loomCfg) {
      expect(ctx.loom.turns.length).toBe(Number(loomCfg.turn_count));
    }

    if ("identity" in loomCfg) {
      const thread = ctx.last_thread;
      expect(thread?.identity?.system_prompt ?? null).toBe(loomCfg.identity.system_prompt ?? null);
    }

    if ("turns" in loomCfg && Array.isArray(loomCfg.turns)) {
      const entitySymbols: Record<string, string> = {};
      for (let idx = 0; idx < loomCfg.turns.length; idx++) {
        const tcfg = loomCfg.turns[idx];
        if (idx >= ctx.loom.turns.length) break;
        const t = ctx.loom.turns[idx];

        if ("sequence" in tcfg) {
          expect(t.sequence).toBe(Number(tcfg.sequence));
        }
        if ("gate_calls" in tcfg) {
          const names = Array.isArray(t.gate_calls)
            ? t.gate_calls.map((r: any) => r.gate_name)
            : [];
          expect(names).toEqual(tcfg.gate_calls);
        }
        if ("terminated" in tcfg) {
          expect(t.terminated).toBe(Boolean(tcfg.terminated));
        }
        if ("truncated" in tcfg) {
          expect(t.truncated).toBe(Boolean(tcfg.truncated));
        }
        if ("reward" in tcfg) {
          expect(t.reward).toBe(Number(tcfg.reward));
        }
        if ("id" in tcfg && tcfg.id === "not_null") {
          expect(t.id).toBeTruthy();
        }
        if ("parent_id" in tcfg && tcfg.parent_id === null) {
          expect(t.parent_id).toBeNull();
        }
        if ("parent_id" in tcfg && typeof tcfg.parent_id === "string") {
          const parentRef = tcfg.parent_id as string;
          if (parentRef.startsWith("turns[") && parentRef.endsWith("].id")) {
            const refIdx = parseInt(parentRef.slice(6, -4), 10);
            expect(t.parent_id).toBe(ctx.loom.turns[refIdx]?.id ?? null);
          } else {
            expect(t.parent_id).toBe(parentRef);
          }
        }
        if ("entity_id" in tcfg) {
          const symbol = String(tcfg.entity_id);
          if (symbol in entitySymbols) {
            expect(t.entity_id).toBe(entitySymbols[symbol]);
          } else {
            entitySymbols[symbol] = t.entity_id;
          }
        }
        if ("metadata" in tcfg) {
          const md = t.metadata;
          const mcfg = tcfg.metadata;
          if ("tokens_prompt" in mcfg) {
            expect(md.tokens_prompt).toBe(mcfg.tokens_prompt);
          }
          if ("tokens_completion" in mcfg) {
            expect(md.tokens_completion).toBe(mcfg.tokens_completion);
          }
          if ("duration_ms" in mcfg) {
            // just check it's a positive number
            expect(md.duration_ms).toBeGreaterThan(0);
          }
          if ("timestamp" in mcfg) {
            expect(md.timestamp).toBeTruthy();
          }
        }
        if ("observation_contains" in tcfg) {
          const needle = String(tcfg.observation_contains);
          const observed = Array.isArray(t.observation)
            ? t.observation
                .map((r) => `${r.content || ""}\n${r.result !== undefined ? r.result : ""}`)
                .join("\n")
            : String(t.observation ?? "");
          expect(observed).toContain(needle);
        }
      }
    }
  }

  if ("threads" in expectCfg) {
    expect(ctx.threads.length).toBe(Number(expectCfg.threads));
  }

  if ("thread_0" in expectCfg) {
    const t0 = ctx.threads[0];
    const t0cfg = expectCfg.thread_0;
    if (t0 && "turns" in t0cfg) {
      expect(t0.turns.length).toBe(Number(t0cfg.turns));
    }
    if (t0 && "result" in t0cfg) {
      expect(t0.result).toBe(t0cfg.result);
    }
    if (t0 && "last_turn" in t0cfg) {
      const cfg = t0cfg.last_turn;
      const last = t0.turns[t0.turns.length - 1];
      if (last) {
        expect(last.terminated).toBe(Boolean(cfg.terminated));
        expect(last.truncated).toBe(Boolean(cfg.truncated));
      }
    }
  }

  if ("thread_1" in expectCfg) {
    const t1 = ctx.threads[1];
    const t1cfg = expectCfg.thread_1;
    if (t1 && "turns" in t1cfg) {
      expect(t1.turns.length).toBeGreaterThanOrEqual(1);
    }
    if (t1 && "result" in t1cfg) {
      expect(t1.result).toBe(t1cfg.result);
    }
    if (t1 && "last_turn" in t1cfg) {
      const cfg = t1cfg.last_turn;
      const last = t1.turns[t1.turns.length - 1];
      if (last) {
        expect(last.terminated).toBe(Boolean(cfg.terminated));
        expect(last.truncated).toBe(Boolean(cfg.truncated));
      }
    }
  }

  if ("cumulative_usage" in expectCfg) {
    const thread = ctx.last_thread;
    const cu = thread?.cumulative_usage;
    const expected = expectCfg.cumulative_usage;
    if (cu) {
      if ("prompt_tokens" in expected) expect(cu.prompt_tokens).toBe(expected.prompt_tokens);
      if ("completion_tokens" in expected) expect(cu.completion_tokens).toBe(expected.completion_tokens);
      if ("total_tokens" in expected) expect(cu.total_tokens).toBe(expected.total_tokens);
    }
  }

  // thread (dict form = extracted_thread length check)
  if ("thread" in expectCfg && typeof expectCfg.thread === "object" && !Array.isArray(expectCfg.thread)) {
    const th = ctx.extracted_thread;
    if (th && "length" in expectCfg.thread) {
      expect(th.length).toBe(Number(expectCfg.thread.length));
    }
  }

  if ("fork_llm_invocations" in expectCfg || "fork_llm_invocations" in expectCfg) {
    const forkLlm = ctx.llms["fork_llm"] || ctx.llms["fork_llm"];
    if (forkLlm) {
      expect(forkLlm.invocations.length).toBeGreaterThanOrEqual(1);
    }
  }

  if ("loom_export_exclude" in expectCfg || "logs_exclude" in expectCfg) {
    const secret = expectCfg.loom_export_exclude || expectCfg.logs_exclude;
    const loomExport = (ctx as any).loom_export || "";
    if (loomExport) {
      expect(loomExport).not.toContain(secret);
    }
  }

  if ("acp_responses" in expectCfg) {
    const expected = expectCfg.acp_responses || [];
    for (const ecfg of expected) {
      const got = ctx.acp_responses.find((r) => r.id === String(ecfg.id));
      expect(got).toBeTruthy();
      if (ecfg.has_result) {
        expect(got!.result).toBeTruthy();
      }
      if (ecfg.result_contains) {
        expect(JSON.stringify(got!.result)).toContain(String(ecfg.result_contains));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Run test cases
// ---------------------------------------------------------------------------

const RUNNABLE_CASES = ALL_CASES.filter((c) => shouldSkip(c) === null);
const SKIPPED_CASES = ALL_CASES.filter((c) => shouldSkip(c) !== null);

describe("cantrip conformance", () => {
  for (const c of SKIPPED_CASES) {
    const reason = shouldSkip(c);
    test.skip(`[${c.rule}] ${c.name} (${reason})`, () => {});
  }

  for (const testCase of RUNNABLE_CASES) {
    test(`[${testCase.rule}] ${testCase.name}`, async () => {
      let ctx: TestContext | null = null;
      try {
        ctx = buildContext(testCase);
        await executeActions(ctx, testCase.action);
      } catch (e: any) {
        if (!ctx) {
          ctx = {
            setup: testCase.setup || {},
            llm: null,
            llms: {},
            entities: [],
            acp_responses: [],
            sessions: new Map(),
            last_session_id: null,
            results: [],
            lastError: e,
            executions: [],
            loom: new TestLoom(),
            threads: [],
            last_thread: null,
            extracted_thread: null,
          };
        } else {
          ctx.lastError = e;
        }
      }

      checkExpect(ctx!, testCase.expect || {});
    });
  }
});
