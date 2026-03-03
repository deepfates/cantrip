import type { AnyMessage } from "./llm/messages";
import { generateTurnId, type GateCallRecord, type Turn } from "./loom/turn";

export * from "./loom/index";

/**
 * Compatibility helper used by conformance tests: derive Turn records from flat message history.
 */
export function buildTurnsFromHistory(options: {
  messages: Array<{
    role: string;
    content?: any;
    tool_calls?: any[] | null;
    tool_call_id?: string;
    tool_name?: string;
    is_error?: boolean;
    ephemeral?: boolean;
  }>;
  entity_id: string;
  max_iterations: number;
  usage_per_turn?: Array<{
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
  }>;
  durations_ms?: number[];
  timestamps?: string[];
}): Turn[] {
  const { messages, entity_id, max_iterations, usage_per_turn, durations_ms, timestamps } = options;

  const turns: Turn[] = [];
  let sequence = 0;
  let prevTurnId: string | null = null;

  let i = 0;
  while (i < messages.length) {
    const msg = messages[i];
    if (msg.role === "system" || msg.role === "user") {
      i += 1;
      continue;
    }

    if (msg.role !== "assistant") {
      i += 1;
      continue;
    }

    sequence += 1;
    const turnId = generateTurnId();
    const assistantToolCalls = msg.tool_calls ?? [];

    const observations: GateCallRecord[] = [];
    let j = i + 1;
    while (j < messages.length && messages[j].role === "tool") {
      const tm = messages[j] as any;
      const gate_name = tm.tool_name || "unknown";

      let args: Record<string, any> = {};
      const match = assistantToolCalls.find((tc: any) => tc.id === tm.tool_call_id);
      if (match) {
        try {
          args = JSON.parse(match.function?.arguments ?? "{}");
        } catch {
          args = {};
        }
      }

      const rawContent = tm.content;
      const content =
        typeof rawContent === "string"
          ? rawContent
          : Array.isArray(rawContent)
            ? rawContent.map((p: any) => p?.text ?? "").join("")
            : String(rawContent ?? "");

      observations.push({
        gate_name,
        arguments: JSON.stringify(args),
        result: gate_name === "done" && content.startsWith("Task completed: ")
          ? content.slice("Task completed: ".length)
          : content,
        is_error: Boolean(tm.is_error),
      });
      j += 1;
    }

    const usage = usage_per_turn?.[turns.length];
    const metadata = {
      tokens_prompt: usage?.prompt_tokens ?? 0,
      tokens_completion: usage?.completion_tokens ?? 0,
      tokens_cached: 0,
      duration_ms: durations_ms?.[turns.length] ?? 0,
      timestamp: timestamps?.[turns.length] ?? new Date().toISOString(),
    };

    const utterance = msg.content;
    turns.push({
      id: turnId,
      cantrip_id: entity_id,
      entity_id,
      parent_id: prevTurnId,
      sequence,
      role: "turn",
      utterance: typeof utterance === "string" ? utterance : JSON.stringify(utterance ?? null),
      observation: observations
        .map((o) => String(o.result ?? ""))
        .join("\n"),
      gate_calls: observations,
      reward: null,
      terminated: observations.some((o) => o.gate_name === "done" && !o.is_error),
      truncated: false,
      metadata,
    });
    prevTurnId = turnId;
    i = j;
  }

  return turns;
}

export function historyToMessages(history: Array<{ role: string; content: any }>): AnyMessage[] {
  return history.map((m) => ({ role: m.role as AnyMessage["role"], content: m.content } as AnyMessage));
}
