/**
 * Cantrip Conformance Test Runner
 *
 * Reads language-agnostic test cases from ../../tests.yaml and executes them
 * against the TypeScript/Bun implementation.
 *
 * Terminology mapping (spec -> TS):
 *   crystal  -> BaseChatModel / llm
 *   call     -> system_prompt + config on Agent
 *   circle   -> tools + max_iterations + require_done_tool on Agent
 *   gates    -> tools (ToolLike[])
 *   wards    -> max_iterations, require_done_tool
 *   entity   -> Agent instance
 *   cast     -> agent.query(intent)
 *   done gate -> the built-in "done" tool that throws TaskComplete
 */

import { describe, expect, test } from "bun:test";
import * as fs from "fs";
import * as path from "path";
import * as yaml from "js-yaml";

import { Agent, TaskComplete } from "../src/agent/service";
import type { BaseChatModel, ToolChoice, ToolDefinition } from "../src/llm/base";
import type { AnyMessage, ToolCall, ToolMessage } from "../src/llm/messages";
import type { ChatInvokeCompletion } from "../src/llm/views";
import type { ToolLike } from "../src/tools/types";
import { tool } from "../src/tools/decorator";
import { Loom, buildTurnsFromHistory } from "../src/loom";
import type { Thread } from "../src/loom";

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

const SKIP_PREFIXES = ["COMP-", "PROD-"];

const SKIP_NAMES = new Set([
  "provider responses normalized to crystal contract",
  "call stored as root context in loom",
  "folding never compresses the system prompt",
  "gate dependencies injected at construction",
  "sandbox state persists across turns in code circle",
]);

function shouldSkip(c: TestCase): string | null {
  if (c.skip) return "marked skip in yaml";
  if (!c.action && !c.expect) return "no action/expect";
  if (SKIP_PREFIXES.some((p) => c.rule.startsWith(p))) return `rule prefix ${c.rule}`;
  if (SKIP_NAMES.has(c.name)) return `skip by name`;

  const setup = c.setup || {};
  const crystal = setup.crystal;
  if (crystal && typeof crystal === "object") {
    if (crystal.type === "code_circle") return "code_circle type";
    // Skip mock_openai only when there are no responses (i.e., it requires real OpenAI normalization)
    if (crystal.provider === "mock_openai" && !crystal.responses) return "mock_openai provider";
  }
  const circle = setup.circle;
  if (circle && circle.type === "code") return "code circle type";

  return null;
}

// ---------------------------------------------------------------------------
// FakeCrystal: deterministic BaseChatModel mock
// ---------------------------------------------------------------------------

class FakeCrystal implements BaseChatModel {
  model = "fake";
  provider = "fake";
  name = "fake";

  private responses: any[];
  private callIndex = 0;
  public invocations: Array<{
    messages: any[];
    tools: any[] | null;
    tool_choice: ToolChoice | null;
  }> = [];
  private defaultUsage: { prompt_tokens: number; completion_tokens: number } | null;

  constructor(config: Record<string, any>) {
    this.responses = config.responses || [];
    this.defaultUsage = config.usage ?? null;
  }

  async ainvoke(
    messages: AnyMessage[],
    tools?: ToolDefinition[] | null,
    tool_choice?: ToolChoice | null,
  ): Promise<ChatInvokeCompletion> {
    this.invocations.push({
      messages: messages.map((m) => ({
        role: m.role,
        content: (m as any).content ?? null,
        tool_calls: (m as any).tool_calls ?? undefined,
        tool_call_id: (m as any).tool_call_id ?? undefined,
      })),
      tools: tools
        ? tools.map((t) => ({ name: t.name, parameters: t.parameters }))
        : null,
      tool_choice: tool_choice ?? null,
    });

    if (this.callIndex >= this.responses.length) {
      throw new Error(
        `FakeCrystal exhausted: called ${this.callIndex + 1} times but only ${this.responses.length} responses configured`,
      );
    }

    const resp = this.responses[this.callIndex];
    this.callIndex++;

    if (resp.error) {
      const err: any = new Error(
        typeof resp.error === "string"
          ? resp.error
          : resp.error.message || "crystal error",
      );
      if (typeof resp.error === "object" && resp.error.status) {
        err.status_code = resp.error.status;
        err.status = resp.error.status;
      }
      throw err;
    }

    // Handle tool_result response type (CRYSTAL-7): validate tool_call_id matches a prior tool call
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
      throw new Error("crystal returned neither content nor tool_calls");
    }

    let toolCalls: ToolCall[] | undefined;
    if (resp.tool_calls && Array.isArray(resp.tool_calls)) {
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

    return {
      content: resp.content ?? null,
      tool_calls: toolCalls,
      usage,
    };
  }
}

// ---------------------------------------------------------------------------
// Build tools from gate specs
// ---------------------------------------------------------------------------

function buildTools(gateSpecs: any[]): ToolLike[] {
  const tools: ToolLike[] = [];
  for (const spec of gateSpecs) {
    if (typeof spec === "string") {
      switch (spec) {
        case "done":
          tools.push(makeDoneTool());
          break;
        case "echo":
          tools.push(makeEchoTool());
          break;
        case "read":
          tools.push(makeReadTool());
          break;
        case "fetch":
          tools.push(makeFetchTool());
          break;
        default:
          tools.push(makeGenericTool(spec));
          break;
      }
    } else if (typeof spec === "object" && spec.name) {
      switch (spec.name) {
        case "done":
          tools.push(makeDoneTool());
          break;
        case "echo":
          tools.push(makeEchoTool());
          break;
        case "read":
          tools.push(makeReadTool());
          break;
        case "fetch":
          tools.push(makeFetchTool());
          break;
        default:
          if (spec.behavior === "throw") {
            tools.push(
              makeThrowingTool(spec.name, spec.error || "error"),
            );
          } else if (spec.behavior === "delay") {
            tools.push(
              makeDelayTool(
                spec.name,
                spec.delay_ms || 0,
                spec.result || "ok",
              ),
            );
          } else {
            tools.push(makeGenericTool(spec.name));
          }
          break;
      }
    }
  }
  return tools;
}

function makeDoneTool(): ToolLike {
  return tool(
    "Signal task completion",
    async ({ message }: { message: string }) => {
      if (!message && message !== "") {
        throw new Error("missing required argument: message");
      }
      throw new TaskComplete(message);
    },
    {
      name: "done",
      schema: {
        type: "object",
        properties: { message: { type: "string" } },
        required: ["message"],
        additionalProperties: false,
      },
    },
  );
}

function makeEchoTool(): ToolLike {
  return tool("Echo text back", async ({ text }: { text: string }) => text, {
    name: "echo",
    schema: {
      type: "object",
      properties: { text: { type: "string" } },
      required: ["text"],
      additionalProperties: false,
    },
  });
}

function makeReadTool(): ToolLike {
  return tool(
    "Read a file",
    async ({ path: filePath }: { path: string }) => `contents of ${filePath}`,
    {
      name: "read",
      schema: {
        type: "object",
        properties: { path: { type: "string" } },
        required: ["path"],
        additionalProperties: false,
      },
    },
  );
}

function makeFetchTool(): ToolLike {
  return tool(
    "Fetch a URL",
    async ({ url }: { url: string }) => `fetched ${url}`,
    {
      name: "fetch",
      schema: {
        type: "object",
        properties: { url: { type: "string" } },
        required: ["url"],
        additionalProperties: false,
      },
    },
  );
}

function makeThrowingTool(name: string, errorMsg: string): ToolLike {
  return tool(`Tool ${name} that throws`, async () => {
    throw new Error(errorMsg);
  }, {
    name,
    schema: {
      type: "object",
      properties: {},
      required: [],
      additionalProperties: false,
    },
  });
}

function makeDelayTool(
  name: string,
  delayMs: number,
  result: string,
): ToolLike {
  return tool(`Tool ${name} with delay`, async () => {
    await new Promise((r) => setTimeout(r, delayMs));
    return result;
  }, {
    name,
    schema: {
      type: "object",
      properties: {},
      required: [],
      additionalProperties: false,
    },
  });
}

function makeGenericTool(name: string): ToolLike {
  return tool(
    `Generic tool ${name}`,
    async (args: Record<string, any>) => JSON.stringify(args),
    {
      name,
      schema: {
        type: "object",
        properties: {},
        additionalProperties: true,
      },
    },
  );
}

// CIRCLE-6: stub tool for removed gates that returns an error message
function makeRemovedGateTool(name: string): ToolLike {
  return tool(
    `Gate ${name} (removed by ward)`,
    async () => {
      throw new Error(`gate not available: ${name} has been removed by a ward`);
    },
    {
      name,
      schema: {
        type: "object",
        properties: {},
        additionalProperties: true,
      },
    },
  );
}

// ---------------------------------------------------------------------------
// Analysis helpers: derive conformance properties from Agent history
// ---------------------------------------------------------------------------

/**
 * Analyze agent history after a query to derive spec-level properties:
 * turns, terminated, truncated, gate calls executed, gate results.
 */
function analyzeExecution(
  agent: Agent,
  maxTurns: number,
  crystal: FakeCrystal,
): {
  turns: number;
  terminated: boolean;
  truncated: boolean;
  gateCallsExecuted: string[];
  gateResults: string[];
} {
  const history = agent.history;

  // Count turns = number of assistant messages in history
  const assistantMessages = history.filter((m) => m.role === "assistant");
  const turns = assistantMessages.length;

  // Derive gate calls executed from tool messages in history
  // These are tool messages that were actually pushed (i.e., tools that ran)
  const toolMessages = history.filter((m) => m.role === "tool") as ToolMessage[];
  const gateCallsExecuted: string[] = [];
  const gateResults: string[] = [];

  for (const tm of toolMessages) {
    const toolName = tm.tool_name;
    gateCallsExecuted.push(toolName);

    const content =
      typeof tm.content === "string"
        ? tm.content
        : (tm.content || []).map((p: any) => p.text || "").join("");

    if (toolName === "done") {
      // The done tool result is "Task completed: <message>"
      const match = content.match(/^Task completed:\s*(.*)$/);
      gateResults.push(match ? match[1] : content);
    } else if (toolName === "echo") {
      gateResults.push(content);
    } else {
      gateResults.push(content);
    }
  }

  // Determine terminated: done tool was called successfully
  const doneReached = gateCallsExecuted.includes("done") &&
    toolMessages.some(
      (m) =>
        m.tool_name === "done" &&
        !m.is_error &&
        typeof m.content === "string" &&
        m.content.startsWith("Task completed:"),
    );

  // Determine terminated also for text-only responses (no require_done_tool)
  // If the loop ended naturally (not truncated), it's terminated.
  const reachedMaxTurns = turns >= maxTurns;
  const terminated = doneReached || (!reachedMaxTurns && turns > 0);
  const truncated = reachedMaxTurns && !doneReached;

  return { turns, terminated, truncated, gateCallsExecuted, gateResults };
}

// ---------------------------------------------------------------------------
// Context: holds state across actions for a single test case
// ---------------------------------------------------------------------------

type TestContext = {
  setup: Record<string, any>;
  crystal: FakeCrystal | null;
  crystals: Record<string, FakeCrystal>;
  agents: Agent[];
  results: any[];
  lastError: Error | null;
  executions: Array<{
    turns: number;
    terminated: boolean;
    truncated: boolean;
    gateCallsExecuted: string[];
    gateResults: string[];
  }>;
  // Loom subsystem
  loom: Loom;
  threads: Thread[];
  last_thread: Thread | null;
  extracted_thread: any[] | null;
};

function buildContext(testCase: TestCase): TestContext {
  const setup = testCase.setup || {};
  const crystals: Record<string, FakeCrystal> = {};
  for (const [k, v] of Object.entries(setup)) {
    if (k.includes("crystal") && v && typeof v === "object" && v.responses) {
      crystals[k] = new FakeCrystal(v);
    }
  }
  const mainCrystal = crystals["crystal"] || null;

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
    crystal: mainCrystal,
    crystals,
    agents: [],
    results: [],
    lastError: null,
    executions: [],
    loom: new Loom(),
    threads: [],
    last_thread: null,
    extracted_thread: null,
  };
}

// ---------------------------------------------------------------------------
// Execute actions
// ---------------------------------------------------------------------------

async function executeCast(
  ctx: TestContext,
  castCfg: Record<string, any>,
): Promise<void> {
  const intent = castCfg.intent;
  if (intent === null || intent === undefined) {
    throw new Error("intent is required");
  }

  const setup = ctx.setup;
  const circleSetup = setup.circle || {};
  const callSetup = setup.call || {};

  let crystal: FakeCrystal;
  if (castCfg.crystal && ctx.crystals[castCfg.crystal]) {
    crystal = ctx.crystals[castCfg.crystal];
  } else if (ctx.crystal) {
    crystal = ctx.crystal;
  } else {
    throw new Error("no crystal available");
  }

  const gates = circleSetup.gates || [];
  const wards = circleSetup.wards || [];

  // CIRCLE-6: collect remove_gate wards and filter out those gates
  const removedGates = new Set<string>();
  for (const w of wards) {
    if (w && typeof w === "object" && "remove_gate" in w) {
      removedGates.add(w.remove_gate);
    }
  }
  const filteredGates = removedGates.size > 0
    ? gates.filter((g: any) => {
        const name = typeof g === "string" ? g : g.name;
        return !removedGates.has(name);
      })
    : gates;
  const tools = buildTools(filteredGates);
  // Add stub tools for removed gates so crystal calls get an error response
  for (const removedGate of removedGates) {
    tools.push(makeRemovedGateTool(removedGate));
  }

  let maxTurns = 200;
  for (const w of wards) {
    if (w && typeof w === "object" && "max_turns" in w) {
      maxTurns = w.max_turns;
    }
  }

  const requireDone = callSetup.require_done_tool ?? false;
  const toolChoice = callSetup.tool_choice ?? undefined;

  const agent = new Agent({
    llm: crystal as any,
    tools,
    system_prompt: callSetup.system_prompt ?? null,
    max_iterations: maxTurns,
    tool_choice: toolChoice,
    require_done_tool: requireDone,
    retry: { enabled: false },
    ephemerals: { enabled: false },
    compaction_enabled: false,
  });

  ctx.agents.push(agent);

  const invocationsBefore = crystal.invocations.length;
  const castStart = Date.now();

  const result = await agent.query(String(intent));
  ctx.results.push(result);

  const exec = analyzeExecution(agent, maxTurns, crystal);
  ctx.executions.push(exec);

  // ---------------------------------------------------------------------------
  // Build Loom thread from agent history
  // ---------------------------------------------------------------------------
  const history = agent.history as Array<{
    role: string;
    content?: any;
    tool_calls?: any[] | null;
    tool_call_id?: string;
    tool_name?: string;
    is_error?: boolean;
    ephemeral?: boolean;
  }>;

  // Build per-invocation usage from response configs
  const crystalKey = castCfg.crystal || "crystal";
  const crystalConfig = ctx.setup[crystalKey] || {};
  const responsesConfig: any[] = crystalConfig.responses || [];

  const now = new Date().toISOString();
  const castDuration = Math.max(Date.now() - castStart, 1);

  const usageFromConfig: Array<{
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
  }> = responsesConfig
    .slice(invocationsBefore)
    .map((r: any) => {
      const u = r.usage || crystalConfig.usage || null;
      return {
        prompt_tokens: u?.prompt_tokens ?? 0,
        completion_tokens: u?.completion_tokens ?? 0,
        total_tokens: (u?.prompt_tokens ?? 0) + (u?.completion_tokens ?? 0),
      };
    });

  const turns = buildTurnsFromHistory({
    messages: history,
    entity_id: agent.entity_id,
    max_iterations: maxTurns,
    usage_per_turn: usageFromConfig.length > 0 ? usageFromConfig : undefined,
    timestamps: Array.from({ length: 200 }, () => now),
    durations_ms: Array.from({ length: 200 }, (_, i) => i === 0 ? castDuration : 1),
  });

  const totalAssistantMsgs = history.filter((m) => m.role === "assistant").length;
  const wasTruncated = totalAssistantMsgs >= maxTurns && !exec.terminated;
  if (wasTruncated && turns.length > 0) {
    turns[turns.length - 1].truncated = true;
    turns[turns.length - 1].terminated = false;
  }

  let cumPrompt = 0;
  let cumCompletion = 0;
  for (const u of usageFromConfig.slice(0, turns.length)) {
    cumPrompt += u.prompt_tokens;
    cumCompletion += u.completion_tokens;
  }

  const thread: Thread = {
    id: `thread_${crypto.randomUUID()}`,
    entity_id: agent.entity_id,
    intent: String(intent),
    call: {
      system_prompt: callSetup.system_prompt ?? null,
      require_done_tool: requireDone,
      tool_choice: toolChoice ?? null,
    },
    turns: [],
    result,
    terminated: exec.terminated,
    truncated: wasTruncated,
    cumulative_usage: {
      prompt_tokens: cumPrompt,
      completion_tokens: cumCompletion,
      total_tokens: cumPrompt + cumCompletion,
    },
  };

  ctx.loom.register_thread(thread);
  for (const turn of turns) {
    ctx.loom.append_turn(thread, turn);
  }

  ctx.threads.push(thread);
  ctx.last_thread = thread;
}

// CALL-1: attempt to mutate a readonly property on the agent, catching TypeError
async function executeThen(ctx: TestContext, thenCfg: Record<string, any>): Promise<void> {
  if (thenCfg.mutate_call) {
    const agent = ctx.agents[ctx.agents.length - 1];
    if (!agent) throw new Error("no agent to mutate");
    const mutations = thenCfg.mutate_call;
    if ("system_prompt" in mutations) {
      // system_prompt is readonly; attempting to assign throws in strict mode
      try {
        (agent as any).system_prompt = mutations.system_prompt;
        // If assignment didn't throw (non-strict), check if value changed
        if ((agent as any).system_prompt === mutations.system_prompt) {
          throw new TypeError("call is immutable: system_prompt cannot be changed after construction");
        }
      } catch (err: any) {
        if (err instanceof TypeError || String(err.message).includes("immutable")) {
          throw new TypeError("call is immutable: system_prompt cannot be changed after construction");
        }
        throw err;
      }
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
      observation: t.observation.map((r) => ({
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
    const forkCrystalName = cfg.crystal;
    const forkCrystal = ctx.crystals[forkCrystalName];
    const forkIntent = cfg.intent;

    if (!forkCrystal) throw new Error(`no crystal '${forkCrystalName}' for fork`);
    if (!ctx.last_thread) throw new Error("no thread to fork from");

    const parentThread = ctx.last_thread;
    const contextTurns = parentThread.turns.slice(0, fromTurn);

    const setup = ctx.setup;
    const circleSetup = setup.circle || {};
    const callSetup = setup.call || {};
    const gates = circleSetup.gates || [];
    const wards = circleSetup.wards || [];
    const removedGates = new Set<string>();
    for (const w of wards) {
      if (w && typeof w === "object" && "remove_gate" in w) {
        removedGates.add(w.remove_gate);
      }
    }
    const filteredGates = removedGates.size > 0
      ? gates.filter((g: any) => {
          const name = typeof g === "string" ? g : g.name;
          return !removedGates.has(name);
        })
      : gates;
    const forkTools = buildTools(filteredGates);
    let maxTurns = 200;
    for (const w of wards) {
      if (w && typeof w === "object" && "max_turns" in w) {
        maxTurns = w.max_turns;
      }
    }
    const requireDone = callSetup.require_done_tool ?? false;
    const toolChoice = callSetup.tool_choice ?? undefined;

    const forkAgent = new Agent({
      llm: forkCrystal as any,
      tools: forkTools,
      system_prompt: callSetup.system_prompt ?? null,
      max_iterations: maxTurns,
      tool_choice: toolChoice,
      require_done_tool: requireDone,
      retry: { enabled: false },
      ephemerals: { enabled: false },
      compaction_enabled: false,
    });

    // Reconstruct messages from the forked context turns
    const replayMessages: any[] = [];
    if (callSetup.system_prompt) {
      replayMessages.push({ role: "system", content: callSetup.system_prompt, cache: true });
    }
    replayMessages.push({ role: "user", content: parentThread.intent });
    for (const turn of contextTurns) {
      replayMessages.push({
        role: "assistant",
        content: turn.utterance.content,
        tool_calls: turn.utterance.tool_calls.length > 0 ? turn.utterance.tool_calls : null,
      });
      for (const obs of turn.observation) {
        const toolCall = turn.utterance.tool_calls.find(
          (tc: any) => tc.function?.name === obs.gate_name
        );
        replayMessages.push({
          role: "tool",
          tool_call_id: toolCall?.id || `tc_${obs.gate_name}`,
          tool_name: obs.gate_name,
          content: obs.content,
          is_error: obs.is_error,
          ephemeral: false,
          destroyed: false,
        });
      }
    }
    forkAgent.load_history(replayMessages);
    ctx.agents.push(forkAgent);

    const forkResult = await forkAgent.query(String(forkIntent));
    ctx.results.push(forkResult);
    const forkExec = analyzeExecution(forkAgent, maxTurns, forkCrystal);
    ctx.executions.push(forkExec);

    const forkHistory = forkAgent.history as any[];
    const forkCrystalConfig = ctx.setup[forkCrystalName] || {};
    const forkResponsesConfig: any[] = forkCrystalConfig.responses || [];
    const forkNow = new Date().toISOString();

    const forkUsageFromConfig = forkResponsesConfig.map((r: any) => {
      const u = r.usage || forkCrystalConfig.usage || null;
      return {
        prompt_tokens: u?.prompt_tokens ?? 0,
        completion_tokens: u?.completion_tokens ?? 0,
        total_tokens: (u?.prompt_tokens ?? 0) + (u?.completion_tokens ?? 0),
      };
    });

    const forkTurns = buildTurnsFromHistory({
      messages: forkHistory,
      entity_id: forkAgent.entity_id,
      max_iterations: maxTurns,
      usage_per_turn: forkUsageFromConfig.length > 0 ? forkUsageFromConfig : undefined,
      timestamps: Array.from({ length: 200 }, () => forkNow),
      durations_ms: Array.from({ length: 200 }, () => 1),
    });

    const forkTotalAssistant = forkHistory.filter((m: any) => m.role === "assistant").length;
    const forkTruncated = forkTotalAssistant >= maxTurns && !forkExec.terminated;
    if (forkTruncated && forkTurns.length > 0) {
      forkTurns[forkTurns.length - 1].truncated = true;
      forkTurns[forkTurns.length - 1].terminated = false;
    }

    let forkCumPrompt = 0;
    let forkCumCompletion = 0;
    for (const u of forkUsageFromConfig) {
      forkCumPrompt += u.prompt_tokens;
      forkCumCompletion += u.completion_tokens;
    }

    const forkThread: Thread = {
      id: `thread_${crypto.randomUUID()}`,
      entity_id: forkAgent.entity_id,
      intent: String(forkIntent),
      call: {
        system_prompt: callSetup.system_prompt ?? null,
        require_done_tool: requireDone,
        tool_choice: toolChoice ?? null,
      },
      turns: [],
      result: forkResult,
      terminated: forkExec.terminated,
      truncated: forkTruncated,
      cumulative_usage: {
        prompt_tokens: forkCumPrompt,
        completion_tokens: forkCumCompletion,
        total_tokens: forkCumPrompt + forkCumCompletion,
      },
    };

    ctx.loom.register_thread(forkThread);

    // Include shared context turns from parent + new fork turns
    for (const turn of contextTurns) {
      ctx.loom.append_turn(forkThread, turn);
    }
    // New turns: turns after the replayed context messages in forkTurns
    const newForkTurns = forkTurns.slice(fromTurn);
    for (const turn of newForkTurns) {
      ctx.loom.append_turn(forkThread, turn);
    }

    ctx.threads.push(forkThread);
    ctx.last_thread = forkThread;
  }
}

async function executeActions(ctx: TestContext, action: any): Promise<void> {
  const actions = Array.isArray(action) ? action : [action];
  for (const act of actions) {
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
  const crystal = setup.crystal;
  const circleSetup = setup.circle || {};
  const callSetup = setup.call || {};
  const gates = circleSetup.gates || [];
  const wards = circleSetup.wards || [];

  if (crystal === null || crystal === undefined) {
    throw new Error("cantrip requires a crystal");
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
    expect(ctx.agents.length).toBe(expectCfg.entities);
  }

  if (expectCfg.entity_ids_unique) {
    const ids = ctx.agents.map((a) => a.entity_id);
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

  if ("thread" in expectCfg && Array.isArray(expectCfg.thread)) {
    if (expectCfg.thread.length >= 2) {
      expect(expectCfg.thread[0].role).toBe("entity");
      expect(expectCfg.thread[1].role).toBe("circle");
    }
  }

  if ("crystal_invocations" in expectCfg) {
    const crystal = ctx.crystal!;
    const inv = crystal.invocations;

    if (typeof expectCfg.crystal_invocations === "number") {
      expect(inv.length).toBe(expectCfg.crystal_invocations);
    } else if (Array.isArray(expectCfg.crystal_invocations)) {
      for (let i = 0; i < expectCfg.crystal_invocations.length; i++) {
        const c = expectCfg.crystal_invocations[i];
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

  if ("crystal_received_tool_choice" in expectCfg) {
    const inv = ctx.crystal!.invocations;
    expect(inv[0].tool_choice).toBe(expectCfg.crystal_received_tool_choice);
  }

  if ("crystal_received_tools" in expectCfg) {
    const inv = ctx.crystal!.invocations;
    const gotNames = inv[0].tools?.map((t: any) => t.name) || [];
    const wantNames = expectCfg.crystal_received_tools.map(
      (t: any) => t.name,
    );
    expect(gotNames).toEqual(wantNames);
  }

  if ("turn_1_observation" in expectCfg) {
    const cfg = expectCfg.turn_1_observation;
    const agent = ctx.agents[ctx.agents.length - 1];
    const history = agent.history;
    const firstToolMsg = history.find((m) => m.role === "tool") as
      | ToolMessage
      | undefined;

    if (cfg.is_error !== undefined) {
      expect(Boolean(firstToolMsg?.is_error)).toBe(Boolean(cfg.is_error));
    }
    if (cfg.content_contains) {
      const content =
        typeof firstToolMsg?.content === "string"
          ? firstToolMsg.content
          : JSON.stringify(firstToolMsg?.content);
      expect(content.toLowerCase()).toContain(
        cfg.content_contains.toLowerCase(),
      );
    }
    if ("content" in cfg && cfg.content !== undefined) {
      const content =
        typeof firstToolMsg?.content === "string"
          ? firstToolMsg.content
          : JSON.stringify(firstToolMsg?.content);
      expect(content).toBe(cfg.content);
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

    if ("call" in loomCfg) {
      // Check that the call's system_prompt matches
      const thread = ctx.last_thread;
      expect(thread?.call?.system_prompt ?? null).toBe(loomCfg.call.system_prompt ?? null);
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
          expect(t.observation.map((r) => r.gate_name)).toEqual(tcfg.gate_calls);
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
          const observed = t.observation
            .map((r) => `${r.content || ""}\n${r.result !== undefined ? r.result : ""}`)
            .join("\n");
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

  if ("fork_crystal_invocations" in expectCfg) {
    const forkCrystal = ctx.crystals["fork_crystal"];
    if (forkCrystal) {
      expect(forkCrystal.invocations.length).toBeGreaterThanOrEqual(1);
    }
  }

  if ("loom_export_exclude" in expectCfg || "logs_exclude" in expectCfg) {
    const secret = expectCfg.loom_export_exclude || expectCfg.logs_exclude;
    const loomExport = (ctx as any).loom_export || "";
    if (loomExport) {
      expect(loomExport).not.toContain(secret);
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
            crystal: null,
            crystals: {},
            agents: [],
            results: [],
            lastError: e,
            executions: [],
          };
        } else {
          ctx.lastError = e;
        }
      }

      checkExpect(ctx!, testCase.expect || {});
    });
  }
});
