import { TaskComplete } from "../../../entity/service";
import { gate } from "../decorator";
import type { GateResult } from "../gate";

export const done = gate(
  "Signal task completion",
  async ({ message }: { message: string }) => {
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

/**
 * Done gate variant for the JS medium.
 *
 * Presented as `submit_answer(result)` in the sandbox via docs.sandbox_name.
 * Throws SIGNAL_FINAL so the error propagates correctly through QuickJS
 * (which stringifies thrown errors — TaskComplete wouldn't survive the boundary).
 */
export function done_for_medium(): GateResult {
  return {
    name: "done",
    definition: {
      name: "done",
      description: "Signal task completion",
      parameters: {
        type: "object",
        properties: { message: { type: "string" } },
        required: ["message"],
        additionalProperties: false,
      },
    },
    ephemeral: false,
    docs: {
      sandbox_name: "submit_answer",
      signature: "submit_answer(result)",
      description:
        "Terminates the task and returns `result` to the user. This is the ONLY way to finish.",
      section: "HOST FUNCTIONS",
    },
    execute: async (args: Record<string, unknown>) => {
      // The medium maps positional args: submit_answer("result") → { message: "result" }
      // But submit_answer({...obj}) hits the single-object shortcut, passing the obj directly.
      // Handle both: if args.message exists, use it; otherwise the args object IS the value.
      const value = "message" in args ? args.message : args;
      const message =
        typeof value === "string" ? value : JSON.stringify(value, null, 2);
      // Use SIGNAL_FINAL so it propagates through QuickJS sandbox correctly
      throw new Error(`SIGNAL_FINAL:${message}`);
    },
  };
}

export const defaultGates = [done];
