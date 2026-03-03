// ── Cantrip ─────────────────────────────────────────────────────────
// Public API surface. Import from here unless you need deep internals.

// ── LLM (the model) ─────────────────────────────────────────────────
export { ChatAnthropic } from "./llm/anthropic/chat";
export { ChatOpenAI } from "./llm/openai/chat";
export { ChatOpenAILike } from "./llm/openai/like";
export { ChatGoogle } from "./llm/google/chat";
export { ChatLMStudio } from "./llm/lmstudio/chat";
export { ChatOpenRouter } from "./llm/openrouter/chat";
export type {
  BaseChatModel,
  ToolChoice,
  GateDefinition,
} from "./llm/base";
export type { ChatInvokeUsage, ChatInvokeCompletion } from "./llm/views";
export * from "./llm/messages";

// ── LLM / Tokens ────────────────────────────────────────────────────
export * from "./llm/tokens";

// ── Circle (the environment) ────────────────────────────────────────
export { Circle } from "./circle/circle";
export type { CircleExecuteResult, CircleGateCall } from "./circle/circle";
export type { Medium } from "./circle/medium";
export { js } from "./circle/medium/js";
export { getJsMediumSandbox } from "./circle/medium/js";
export type { JsMediumOptions } from "./circle/medium/js";
export type { CantripMediumConfig } from "./circle/gate/builtin/cantrip";
export { cantripGates } from "./circle/gate/builtin/cantrip";
export { jsBrowser } from "./circle/medium/js_browser";
export type { JsBrowserMediumOptions } from "./circle/medium/js_browser";
export { browser } from "./circle/medium/browser";
export type { BrowserMediumOptions } from "./circle/medium/browser";
export { bash } from "./circle/medium/bash";
export type { BashMediumOptions } from "./circle/medium/bash";
export { vm } from "./circle/medium/vm";
export type { VmMediumOptions } from "./circle/medium/vm";
export type { Ward, ResolvedWard } from "./circle/ward";
export {
  DEFAULT_WARD,
  max_turns,
  require_done,
  max_depth,
  resolveWards,
} from "./circle/ward";

// ── Circle / Gate (tool framework) ──────────────────────────────────
export { Gate, gate, serializeBoundGate } from "./circle/gate/decorator";
export { Depends } from "./circle/gate/depends";
export { rawGate } from "./circle/gate/raw";
export { GateSchema, GateSchemaBuilder } from "./circle/gate/schema";
export type {
  GateContent,
  GateHandler,
  GateOptions,
} from "./circle/gate/decorator";
export type {
  DependencyOverrides,
  DependencyFactory,
} from "./circle/gate/depends";
export type {
  RawGateDefinition,
  RawGateHandler,
  RawGateOptions,
} from "./circle/gate/raw";
export type { BoundGate } from "./circle/gate/gate";
export type { GateSchemaFieldOptions } from "./circle/gate/schema";

// ── Circle / Gate / Builtins ────────────────────────────────────────
export { done, defaultGates } from "./circle/gate/builtin/done";
export {
  safeFsGates,
  SandboxContext,
  getSandboxContext,
} from "./circle/gate/builtin/fs";
export {
  repoGates,
  RepoContext,
  getRepoContext,
  getRepoContextDepends,
} from "./circle/gate/builtin/repo";
export { JsContext, getJsContext } from "./circle/medium/js/context";
export {
  BrowserContext,
  getBrowserContext,
} from "./circle/medium/browser/context";
export {
  call_entity as call_entity_gate,
  call_entity_batch as call_entity_batch_gate,
  currentTurnIdBinding,
  spawnBinding,
  progressBinding,
  depthBinding,
} from "./circle/gate/builtin/call_entity_gate";
export type {
  CallEntityGateOptions,
  SpawnFn,
} from "./circle/gate/builtin/call_entity_gate";

// ── Cantrip (the script — primary public API) ──────────────────────
export { cantrip } from "./cantrip/cantrip";
export { Entity } from "./cantrip/entity";
export type { EntityOptions } from "./cantrip/entity";
export type { Cantrip, CantripInput } from "./cantrip/cantrip";
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
export {
  deriveThread,
  threadToMessages,
  type Thread,
  type ThreadState,
} from "./loom/thread";
export {
  type Turn,
  type GateCallRecord,
  type TurnMetadata,
  generateTurnId,
} from "./loom/turn";
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
export { TaskComplete } from "./entity/recording";
export {
  createConsoleRenderer,
  patchStderrForEntities,
} from "./entity/console";
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
  type TurnEvent,
} from "./entity/events";

// ── Entity / ACP (protocol adapter) ─────────────────────────────────
export { serveCantripACP, createAcpProgressCallback } from "./entity/acp";
export type {
  CantripEntityFactory,
  CantripSessionHandle,
  CantripSessionContext,
} from "./entity/acp";
