/**
 * Non-destructive folding — SPEC.md §6.8.
 *
 * LOOM-5: Folding MUST NOT destroy history. Full turns remain accessible.
 *         Folding produces a view, not a mutation.
 * LOOM-6: Folding MUST NOT compress the call. System prompt and gate
 *         definitions MUST always be present in the entity's context.
 *
 * Folding replaces a range of turns in the working context with a summary
 * node. The original turns remain in the loom. This is a view transformation.
 */

import type { BaseChatModel } from "../crystal/crystal";
import type { AnyMessage } from "../crystal/messages";
import type { Turn } from "./turn";
import type { Thread } from "./thread";

/** Configuration for folding behavior. */
export type FoldingConfig = {
  /** Folding is enabled. Defaults to true. */
  enabled: boolean;
  /** Trigger when context exceeds this ratio of the crystal's window. Default 0.8. */
  threshold_ratio: number;
  /** Prompt used to generate the fold summary. */
  summary_prompt: string;
  /** Number of recent turns to keep verbatim (not folded). */
  recent_turns_to_keep: number;
};

export const DEFAULT_FOLDING_CONFIG: FoldingConfig = {
  enabled: true,
  threshold_ratio: 0.8,
  summary_prompt: `Summarize the preceding turns concisely. Capture:
1. Key decisions and their rationale
2. Important discoveries and constraints
3. Current state of progress
4. What was attempted and the outcomes

Be concise but preserve actionable detail. This summary replaces the detailed turns in the working context, but the full history is preserved in the loom.`,
  recent_turns_to_keep: 7,
};

/** A fold record — the summary that replaces a range of turns in context. */
export type FoldRecord = {
  /** Turn IDs that were folded (still exist in loom). */
  folded_turn_ids: string[];
  /** The summary text that replaces them in context. */
  summary: string;
  /** First turn sequence number in the folded range. */
  from_sequence: number;
  /** Last turn sequence number in the folded range. */
  to_sequence: number;
};

/** Result of a folding operation. */
export type FoldResult = {
  folded: boolean;
  fold_record: FoldRecord | null;
  /** Messages with folded turns replaced by the summary. */
  messages: AnyMessage[];
  /** Original token count (estimated from turn count). */
  original_turn_count: number;
  /** Remaining verbatim turn count. */
  remaining_turn_count: number;
};

/**
 * Determine which turns to fold in a thread.
 * Keeps recent_turns_to_keep turns verbatim, folds the rest.
 * Returns the turns to fold (oldest first) and turns to keep.
 */
export function partitionForFolding(
  thread: Thread,
  config: FoldingConfig,
): { toFold: Turn[]; toKeep: Turn[] } {
  const turns = thread.turns;
  if (turns.length <= config.recent_turns_to_keep) {
    return { toFold: [], toKeep: turns };
  }
  const splitIndex = turns.length - config.recent_turns_to_keep;
  return {
    toFold: turns.slice(0, splitIndex),
    toKeep: turns.slice(splitIndex),
  };
}

/**
 * Check whether folding should trigger based on token usage.
 * PROD-4: Folding MUST trigger automatically when context approaches limit.
 */
export function shouldFold(
  totalTokens: number,
  contextWindow: number,
  config: FoldingConfig,
): boolean {
  if (!config.enabled) return false;
  const threshold = Math.floor(contextWindow * config.threshold_ratio);
  return totalTokens >= threshold;
}

/**
 * Perform non-destructive folding on a thread.
 *
 * This calls the crystal to summarize the older turns, then returns
 * a new message array with the summary replacing the folded range.
 * The original turns remain in the loom untouched.
 *
 * @param turnsToFold - The turns being summarized (oldest portion)
 * @param turnsToKeep - The recent turns kept verbatim
 * @param llm - Crystal to generate the summary
 * @param config - Folding configuration
 * @returns FoldResult with the new messages and fold metadata
 */
export async function fold(
  turnsToFold: Turn[],
  turnsToKeep: Turn[],
  llm: BaseChatModel,
  config: FoldingConfig = DEFAULT_FOLDING_CONFIG,
): Promise<FoldResult> {
  if (turnsToFold.length === 0) {
    return {
      folded: false,
      fold_record: null,
      messages: [],
      original_turn_count: turnsToKeep.length,
      remaining_turn_count: turnsToKeep.length,
    };
  }

  // Build a summary request from the turns to fold
  const summaryInput: AnyMessage[] = [];
  for (const turn of turnsToFold) {
    if (turn.utterance) {
      summaryInput.push({ role: "assistant", content: turn.utterance } as AnyMessage);
    }
    if (turn.observation) {
      summaryInput.push({ role: "user", content: turn.observation } as AnyMessage);
    }
  }
  summaryInput.push({ role: "user", content: config.summary_prompt } as AnyMessage);

  const response = await llm.ainvoke(summaryInput);
  const summary = extractSummary(response.content ?? "");

  const fromSeq = turnsToFold[0].sequence;
  const toSeq = turnsToFold[turnsToFold.length - 1].sequence;

  const foldRecord: FoldRecord = {
    folded_turn_ids: turnsToFold.map((t) => t.id),
    summary,
    from_sequence: fromSeq,
    to_sequence: toSeq,
  };

  // Build new message array: [fold summary] + [recent turns as messages]
  // LOOM-6: The call (system prompt, gate defs) is NOT included here —
  // it's the caller's responsibility to prepend the system prompt.
  const messages: AnyMessage[] = [
    {
      role: "user",
      content: `[Folded: turns ${fromSeq}-${toSeq}]\n\n${summary}`,
    } as AnyMessage,
  ];

  // Append recent turns as verbatim messages (SPEC §6.8)
  for (const turn of turnsToKeep) {
    if (turn.utterance) {
      messages.push({ role: "assistant", content: turn.utterance } as AnyMessage);
    }
    if (turn.observation) {
      messages.push({ role: "user", content: turn.observation } as AnyMessage);
    }
  }

  return {
    folded: true,
    fold_record: foldRecord,
    messages,
    original_turn_count: turnsToFold.length + turnsToKeep.length,
    remaining_turn_count: turnsToKeep.length,
  };
}

/** Extract summary from possible <summary> tags. */
function extractSummary(text: string): string {
  const match = text.match(/<summary>([\s\S]*?)<\/summary>/i);
  return match ? match[1].trim() : text.trim();
}
