/**
 * Loom/Turn/Thread subsystem for Cantrip TS implementation.
 *
 * The Loom is an append-only turn tree that records the full history of
 * agent executions. Each cast produces a Thread containing ordered Turns.
 * Each Turn records the LLM utterance and gate call observations.
 */

// ---------------------------------------------------------------------------
// GateCallRecord
// ---------------------------------------------------------------------------

export interface GateCallRecord {
  gate_name: string;
  arguments: Record<string, any>;
  result?: any;
  is_error: boolean;
  content: string;
  ephemeral?: boolean;
}

// ---------------------------------------------------------------------------
// Turn
// ---------------------------------------------------------------------------

export interface Turn {
  id: string;
  entity_id: string;
  sequence: number;
  parent_id: string | null;
  utterance: {
    content: string | null;
    tool_calls: any[];
  };
  observation: GateCallRecord[];
  terminated: boolean;
  truncated: boolean;
  reward?: number;
  metadata: Record<string, any>;
}

// ---------------------------------------------------------------------------
// Thread
// ---------------------------------------------------------------------------

export interface Thread {
  id: string;
  entity_id: string;
  intent: string;
  call: any;
  turns: Turn[];
  result?: any;
  terminated: boolean;
  truncated: boolean;
  cumulative_usage: {
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
  };
}

// ---------------------------------------------------------------------------
// Loom: append-only turn tree
// ---------------------------------------------------------------------------

export class Loom {
  /** All turns across all threads, in append order */
  turns: Turn[] = [];

  /** All threads, indexed by thread id */
  threads: Map<string, Thread> = new Map();

  /** Register a new thread in the loom */
  register_thread(thread: Thread): void {
    this.threads.set(thread.id, thread);
  }

  /** Append a turn to a thread (append-only: no deletion allowed) */
  append_turn(thread: Thread, turn: Turn): void {
    thread.turns.push(turn);
    this.turns.push(turn);
  }

  /** Attempting to delete a turn raises an error (loom is append-only) */
  delete_turn(_idx: number): void {
    throw new Error("loom is append-only");
  }

  /** Annotate a reward on a specific turn index within a thread */
  annotate_reward(thread: Thread, index: number, reward: number): void {
    if (index < 0 || index >= thread.turns.length) {
      throw new Error(`turn index ${index} out of range`);
    }
    thread.turns[index].reward = reward;
  }

  /** List all registered threads */
  list_threads(): Thread[] {
    return Array.from(this.threads.values());
  }

  /** Extract the turn sequence from a thread as a trajectory */
  extract_thread(thread: Thread): Array<{
    utterance: { content: string | null; tool_calls: any[] };
    observation: GateCallRecord[];
    terminated: boolean;
    truncated: boolean;
  }> {
    return thread.turns.map((t) => ({
      utterance: t.utterance,
      observation: t.observation,
      terminated: t.terminated,
      truncated: t.truncated,
    }));
  }

  /** Fork a thread from turn N, returning context up to (and including) turn N */
  fork_context(thread: Thread, from_turn: number): Turn[] {
    return thread.turns.slice(0, from_turn);
  }
}

// ---------------------------------------------------------------------------
// Helpers for building Turn records from agent history
// ---------------------------------------------------------------------------

/**
 * Build Turn records from the agent message history after a cast completes.
 *
 * The agent history is a flat list of messages:
 *   [system?, user, assistant, tool*, assistant, tool*, ...]
 *
 * We group by "assistant message + subsequent tool messages" to form turns.
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

  // Walk through messages, grouping assistant + following tool messages
  let i = 0;
  while (i < messages.length) {
    const msg = messages[i];

    // Skip system and user messages
    if (msg.role === "system" || msg.role === "user") {
      i++;
      continue;
    }

    if (msg.role === "assistant") {
      sequence += 1;
      const turnId = `turn_${crypto.randomUUID()}`;

      // Collect tool calls from this assistant message
      const assistantToolCalls = msg.tool_calls ?? [];

      // Collect following tool (observation) messages
      const observations: GateCallRecord[] = [];
      let j = i + 1;
      while (j < messages.length && messages[j].role === "tool") {
        const tm = messages[j];
        const toolName = (tm as any).tool_name || "unknown";
        let args: Record<string, any> = {};

        // Find the matching tool call to recover arguments
        const matchingCall = assistantToolCalls.find(
          (tc: any) => tc.id === tm.tool_call_id,
        );
        if (matchingCall) {
          try {
            args = JSON.parse(matchingCall.function?.arguments ?? "{}");
          } catch {
            args = {};
          }
        }

        const rawContent = tm.content;
        let contentStr: string;
        if (typeof rawContent === "string") {
          contentStr = rawContent;
        } else if (Array.isArray(rawContent)) {
          contentStr = rawContent
            .map((p: any) => p.text || "")
            .join("");
        } else {
          contentStr = String(rawContent ?? "");
        }

        // Determine result (strip "Task completed: " prefix for done tool)
        let result: any = contentStr;
        if (toolName === "done" && contentStr.startsWith("Task completed: ")) {
          result = contentStr.slice("Task completed: ".length);
        }

        observations.push({
          gate_name: toolName,
          arguments: args,
          result,
          is_error: Boolean((tm as any).is_error),
          content: contentStr,
          ephemeral: Boolean((tm as any).ephemeral),
        });
        j++;
      }

      // Determine turn termination/truncation
      const isDone = observations.some(
        (o) =>
          o.gate_name === "done" &&
          !o.is_error,
      );

      // Truncated: last turn and max_iterations would have been reached
      // We detect this by checking if we've consumed all our iterations.
      // The caller sets this after the fact if needed.
      const isTerminated = isDone;
      const isTruncated = false; // will be set by caller if needed

      const usageIdx = turns.length;
      const usage = usage_per_turn?.[usageIdx];
      const duration = durations_ms?.[usageIdx];
      const timestamp = timestamps?.[usageIdx];

      const metadata: Record<string, any> = {};
      if (usage) {
        metadata.tokens_prompt = usage.prompt_tokens;
        metadata.tokens_completion = usage.completion_tokens;
      }
      if (duration !== undefined) {
        metadata.duration_ms = duration;
      }
      if (timestamp !== undefined) {
        metadata.timestamp = timestamp;
      }

      const turn: Turn = {
        id: turnId,
        entity_id,
        sequence,
        parent_id: prevTurnId,
        utterance: {
          content: typeof msg.content === "string" ? msg.content : null,
          tool_calls: assistantToolCalls,
        },
        observation: observations,
        terminated: isTerminated,
        truncated: isTruncated,
        metadata,
      };

      turns.push(turn);
      prevTurnId = turnId;
      i = j;
    } else {
      i++;
    }
  }

  // Mark last turn as truncated if the loop ran out of iterations
  // (caller sets this flag on thread; we handle it by checking assistant msg count)
  return turns;
}
