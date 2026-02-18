// ── Cantrip ─────────────────────────────────────────────────────────
// Public API surface. Import from here unless you need deep internals.

// ── Crystal (the model) ─────────────────────────────────────────────
export { ChatAnthropic } from "./crystal/providers/anthropic/chat";
export { ChatOpenAI } from "./crystal/providers/openai/chat";
export { ChatOpenAILike } from "./crystal/providers/openai/like";
export { ChatGoogle } from "./crystal/providers/google/chat";
export { ChatLMStudio } from "./crystal/providers/lmstudio/chat";
export { ChatOpenRouter } from "./crystal/providers/openrouter/chat";
export type { BaseChatModel, ToolChoice, GateDefinition } from "./crystal/crystal";
export type { ChatInvokeUsage, ChatInvokeCompletion } from "./crystal/views";
export * from "./crystal/messages";

// ── Crystal / Tokens ────────────────────────────────────────────────
export * from "./crystal/tokens";

// ── Circle (the environment) ────────────────────────────────────────
export { Circle } from "./circle/circle";
export type { Ward } from "./circle/ward";
export { DEFAULT_WARD, max_turns, require_done } from "./circle/ward";

// ── Circle / Gate (tool framework) ──────────────────────────────────
export { Tool, tool, serializeGateResult } from "./circle/gate/decorator";
export { Depends } from "./circle/gate/depends";
export { rawTool } from "./circle/gate/raw";
export { GateSchema, GateSchemaBuilder } from "./circle/gate/schema";
export type { GateContent, GateHandler, GateOptions } from "./circle/gate/decorator";
export type { DependencyOverrides, DependencyFactory } from "./circle/gate/depends";
export type { RawGateDefinition, RawGateHandler, RawGateOptions } from "./circle/gate/raw";
export type { GateResult } from "./circle/gate/gate";
export type { GateSchemaFieldOptions } from "./circle/gate/schema";

// ── Circle / Gate / Builtins ────────────────────────────────────────
export { done, defaultGates } from "./circle/gate/builtin/done";
export { unsafeFsGates, SandboxContext, getSandboxContext } from "./circle/gate/builtin/fs";
export { js } from "./circle/gate/builtin/js";
export { js_run } from "./circle/gate/builtin/js_run";
export { JsContext, getJsContext } from "./circle/gate/builtin/js_context";
export { browser } from "./circle/gate/builtin/browser";
export { BrowserContext, getBrowserContext } from "./circle/gate/builtin/browser_context";
export { createRlmAgent, createRlmAgentWithMemory } from "./circle/gate/builtin/call_agent";
export type { RlmOptions, RlmMemoryOptions, RlmMemoryAgent } from "./circle/gate/builtin/call_agent";
export { createRlmConsoleRenderer, patchStderrForRlm } from "./circle/gate/builtin/call_agent_console";

// ── Cantrip (the recipe — primary public API) ──────────────────────
export { cantrip } from "./cantrip/cantrip";
export { Entity } from "./cantrip/entity";
export type { Cantrip, CantripInput, CallInput } from "./cantrip/cantrip";
export type { Call, CallHyperparameters } from "./cantrip/call";
export { renderGateDefinitions } from "./cantrip/call";
export type { Intent } from "./cantrip/intent";

// ── Loom (execution record) ─────────────────────────────────────────
export {
  Loom,
  MemoryStorage,
  JsonlStorage,
  type LoomStorage,
} from "./loom/loom";
export { deriveThread, threadToMessages, type Thread, type ThreadState } from "./loom/thread";
export { type Turn, type GateCallRecord, type TurnMetadata, generateTurnId } from "./loom/turn";
export {
  fold,
  shouldFold,
  partitionForFolding,
  type FoldingConfig,
  type FoldRecord,
  type FoldResult,
  DEFAULT_FOLDING_CONFIG,
} from "./loom/folding";

// ── Entity (the running instance) ───────────────────────────────────
export { Agent, TaskComplete } from "./entity/service";
export { CoreAgent } from "./entity/core";
export { createConsoleRenderer } from "./entity/console";
export { exec, runRepl } from "./entity/repl";
export type { ExecOptions, ReplOptions } from "./entity/repl";
export type {
  ConsoleRenderer,
  ConsoleRendererOptions,
  ConsoleRendererState,
} from "./entity/console";
export {
  TextEvent,
  ThinkingEvent,
  ToolCallEvent,
  ToolResultEvent,
  FinalResponseEvent,
  MessageStartEvent,
  MessageCompleteEvent,
  StepStartEvent,
  StepCompleteEvent,
  HiddenUserMessageEvent,
  type AgentEvent,
} from "./entity/events";

// ── Entity / ACP (protocol adapter) ─────────────────────────────────
export { serveCantripACP, createAcpProgressCallback } from "./entity/acp";
export type {
  CantripAgentFactory,
  CantripSessionHandle,
  CantripSessionContext,
} from "./entity/acp";

// ── Observability ───────────────────────────────────────────────────
export {
  Laminar,
  observe,
  observe_debug,
  setObserver,
  getObserver,
  clearObserver,
} from "./entity/observability";
