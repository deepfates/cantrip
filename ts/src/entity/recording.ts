import type { BaseChatModel, GateDefinition } from "../crystal/crystal";
import type { AnyMessage } from "../crystal/messages";
import type { ChatInvokeCompletion } from "../crystal/views";
import {
  fold,
  shouldFold,
  partitionForFolding,
  type FoldingConfig,
} from "../loom/folding";
import { deriveThread } from "../loom/thread";
import { TaskComplete } from "./errors";
import type { Loom } from "../loom/loom";
import { generateTurnId } from "../loom/turn";
import type { Turn } from "../loom/turn";

export { TaskComplete } from "./errors";

// ── Standalone recording functions ──────────────────────────────────

/** Turn data accepted by recordTurn. */
export type TurnData = {
  iteration: number;
  utterance: string;
  observation: string;
  gate_calls: { gate_name: string; arguments: string; result: string; is_error: boolean }[];
  usage: any;
  duration_ms: number;
  terminated: boolean;
  truncated: boolean;
};

/**
 * Record the Call as the loom root turn (CALL-4).
 * Returns the new last_turn_id (the root turn's id), or null if nothing was recorded.
 */
export async function recordCallRoot(params: {
  loom: Loom;
  cantrip_id: string;
  entity_id: string;
  system_prompt: string | null;
  tool_definitions: GateDefinition[];
  /** When this entity is a child, the parent turn that spawned it. */
  parent_turn_id?: string | null;
}): Promise<string> {
  const gateDefinitions = params.tool_definitions
    .map((g) => `- ${g.name}: ${g.description ?? "(no description)"}`)
    .join("\n");

  const turn: Turn = {
    id: generateTurnId(),
    parent_id: params.parent_turn_id ?? null,
    cantrip_id: params.cantrip_id,
    entity_id: params.entity_id,
    sequence: 0,
    role: "call",
    utterance: params.system_prompt ?? "",
    observation: gateDefinitions,
    gate_calls: [],
    metadata: {
      tokens_prompt: 0,
      tokens_completion: 0,
      tokens_cached: 0,
      duration_ms: 0,
      timestamp: new Date().toISOString(),
    },
    reward: null,
    terminated: false,
    truncated: false,
  };

  await params.loom.append(turn);
  return turn.id;
}

/**
 * Record a turn in the loom (LOOM-1).
 * Returns the new last_turn_id.
 */
export async function recordTurn(params: {
  loom: Loom;
  parent_id: string | null;
  cantrip_id: string;
  entity_id: string;
  turnData: TurnData;
}): Promise<string> {
  const turn: Turn = {
    id: generateTurnId(),
    parent_id: params.parent_id,
    cantrip_id: params.cantrip_id,
    entity_id: params.entity_id,
    sequence: params.turnData.iteration,
    utterance: params.turnData.utterance,
    observation: params.turnData.observation,
    gate_calls: params.turnData.gate_calls,
    metadata: {
      tokens_prompt: params.turnData.usage?.prompt_tokens ?? 0,
      tokens_completion: params.turnData.usage?.completion_tokens ?? 0,
      tokens_cached: params.turnData.usage?.prompt_cached_tokens ?? 0,
      duration_ms: params.turnData.duration_ms,
      timestamp: new Date().toISOString(),
    },
    reward: null,
    terminated: params.turnData.terminated,
    truncated: params.turnData.truncated,
  };
  await params.loom.append(turn);
  return turn.id;
}

/**
 * Check whether folding should trigger and, if so, fold older turns.
 * Returns the new messages array if folding occurred, or null if no folding needed.
 */
export async function checkAndFold(params: {
  messages: AnyMessage[];
  loom: Loom;
  last_turn_id: string;
  folding: FoldingConfig;
  folding_enabled: boolean;
  llm: BaseChatModel;
  system_prompt: string | null;
  response: ChatInvokeCompletion;
}): Promise<AnyMessage[] | null> {
  if (!params.folding_enabled) return null;

  const totalTokens =
    (params.response.usage?.prompt_tokens ?? 0) +
    (params.response.usage?.completion_tokens ?? 0);

  const contextWindow = params.llm.context_window ?? 128_000;
  if (!shouldFold(totalTokens, contextWindow, params.folding)) return null;

  const thread = deriveThread(params.loom, params.last_turn_id);
  const { toFold, toKeep } = partitionForFolding(thread, params.folding);
  if (toFold.length === 0) return null;

  const result = await fold(toFold, toKeep, params.llm, params.folding);
  if (!result.folded) return null;

  const newMessages: AnyMessage[] = [];
  if (params.system_prompt) {
    newMessages.push({
      role: "system",
      content: params.system_prompt,
      cache: true,
    } as AnyMessage);
  }
  newMessages.push(...result.messages);
  return newMessages;
}

