/**
 * Thread derivation — convert a root-to-leaf path of Turns into
 * a Message[] suitable for crystal invocation.
 *
 * See SPEC.md §6.2: "A thread is any root-to-leaf path you can walk."
 * See SPEC.md §6.9: The loom MAY be exposed as entity-readable state.
 */

import type { AnyMessage, AssistantMessage, ToolMessage } from "../crystal/messages";
import type { Turn, GateCallRecord } from "./turn";
import type { Loom } from "./loom";

/** Terminal state of a thread (SPEC §6.2). */
export type ThreadState = "terminated" | "truncated" | "active";

/** A thread: a root-to-leaf path through the turn tree. */
export type Thread = {
  turns: Turn[];
  state: ThreadState;
  leafId: string;
};

/**
 * Derive a thread from the loom given a leaf turn ID.
 * Returns the turns in root-to-leaf order with the thread's terminal state.
 */
export function deriveThread(loom: Loom, leafId: string): Thread {
  const turns = loom.getThread(leafId);
  const lastTurn = turns[turns.length - 1];
  let state: ThreadState = "active";
  if (lastTurn.terminated) state = "terminated";
  else if (lastTurn.truncated) state = "truncated";

  return { turns, state, leafId };
}

/**
 * Convert a thread's turns into a Message[] for the crystal.
 *
 * Each turn produces:
 *   1. An assistant message (the utterance + gate calls)
 *   2. Tool messages for each gate call result
 *   3. A user message (the observation), if there are no gate calls
 *
 * The first turn's utterance is special: if the thread starts with
 * a system prompt / intent, it's conveyed as a user message.
 */
export function threadToMessages(thread: Thread): AnyMessage[] {
  const messages: AnyMessage[] = [];

  for (const turn of thread.turns) {
    // CALL-4: Call root turns become a system message
    if (turn.role === "call") {
      if (turn.utterance) {
        messages.push({
          role: "system",
          content: turn.utterance,
          cache: true,
        } as AnyMessage);
      }
      continue;
    }

    // The entity's utterance becomes an assistant message
    if (turn.utterance) {
      const assistantMsg: AssistantMessage = {
        role: "assistant",
        content: turn.utterance,
        tool_calls: turn.gate_calls.length > 0
          ? turn.gate_calls.map(gateCallRecordToGateCall)
          : null,
      };
      messages.push(assistantMsg);
    }

    // Gate call results become tool messages
    if (turn.gate_calls.length > 0) {
      for (const gc of turn.gate_calls) {
        const toolMsg: ToolMessage = {
          role: "tool",
          tool_call_id: `${turn.id}-${gc.gate_name}`,
          tool_name: gc.gate_name,
          content: gc.result,
          is_error: gc.is_error,
        };
        messages.push(toolMsg);
      }
    }

    // The observation becomes a user message (the circle's response)
    if (turn.observation) {
      messages.push({
        role: "user",
        content: turn.observation,
      } as AnyMessage);
    }
  }

  return messages;
}

/** Convert a GateCallRecord to the GateCall shape expected by the crystal. */
function gateCallRecordToGateCall(gc: GateCallRecord) {
  return {
    id: gc.gate_name, // simplified; real impl may use unique IDs
    type: "function" as const,
    function: {
      name: gc.gate_name,
      arguments: gc.arguments,
    },
  };
}
