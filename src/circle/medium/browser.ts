import type { ToolChoice, GateDefinition } from "../../crystal/crystal";
import type { AssistantMessage, ToolMessage } from "../../crystal/messages";
import type { GateResult } from "../gate/gate";
import type { DependencyOverrides } from "../gate/depends";
import type { TurnEvent } from "../../entity/events";
import type { CircleExecuteResult } from "../circle";
import type { Medium } from "../medium";
import { BrowserContext } from "./browser/context";
import { TaskComplete } from "../../entity/errors";
import {
  StepStartEvent,
  StepCompleteEvent,
  ToolCallEvent,
  ToolResultEvent,
  FinalResponseEvent,
} from "../../entity/events";

export type BrowserMediumOptions = {
  /** Headless mode (default: true). */
  headless?: boolean;
  /** Extra Chromium args. */
  args?: string[];
  /** Browser profile: "full" | "interactive" | "readonly". */
  profile?: "full" | "interactive" | "readonly";
  /** Max output characters (default: 9500). */
  maxOutputChars?: number;
};

const DEFAULT_MAX_OUTPUT_CHARS = 9500;

/**
 * Creates a browser medium — a Taiko browser session that the entity works in.
 *
 * Gates are projected into the browser as available commands alongside Taiko.
 * The crystal sees a single `browser` tool with tool_choice: "required".
 * Termination is via `submit_answer(value)` gate projected into the session.
 */
export function browser(opts?: BrowserMediumOptions): Medium {
  let ctx: BrowserContext | null = null;
  let initialized = false;
  let projectedGates: GateResult[] = [];

  const browserToolDefinition: GateDefinition = {
    name: "browser",
    description:
      "Execute Taiko code in the persistent browser session. All Taiko functions are available: goto, click, write, text, button, link, evaluate, etc. Use `return` to get values back. Gates are available as functions. Use submit_answer(value) to return your final result.",
    parameters: {
      type: "object",
      properties: {
        code: { type: "string", description: "Taiko code to execute." },
        timeout_ms: {
          type: "integer",
          description: "Optional execution timeout in milliseconds.",
        },
      },
      required: ["code"],
      additionalProperties: false,
    },
  };

  const medium: Medium = {
    async init(
      gates: GateResult[],
      _dependency_overrides?: DependencyOverrides | null,
    ) {
      if (initialized) return;

      ctx = await BrowserContext.create({
        headless: opts?.headless ?? true,
        args: opts?.args,
        profile: opts?.profile ?? "full",
      });

      projectedGates = gates;
      initialized = true;
    },

    crystalView(): {
      tool_definitions: GateDefinition[];
      tool_choice: ToolChoice;
    } {
      return {
        tool_definitions: [browserToolDefinition],
        tool_choice: { type: "tool", name: "browser" },
      };
    },

    async execute(
      utterance: AssistantMessage,
      options: {
        on_event?: (event: TurnEvent) => void;
        on_tool_result?: (msg: ToolMessage) => void;
      },
    ): Promise<CircleExecuteResult> {
      if (!ctx || !initialized) {
        throw new Error(
          "Browser medium not initialized — call init() first",
        );
      }

      const emit = options.on_event ?? (() => {});
      const messages: ToolMessage[] = [];
      const gate_calls: CircleExecuteResult["gate_calls"] = [];
      const maxChars = opts?.maxOutputChars ?? DEFAULT_MAX_OUTPUT_CHARS;

      for (const toolCall of utterance.tool_calls ?? []) {
        let args: Record<string, any> = {};
        try {
          args = JSON.parse(toolCall.function.arguments ?? "{}");
        } catch {
          args = { _raw: toolCall.function.arguments };
        }

        const code = args.code ?? args._raw ?? "";

        emit(new StepStartEvent(toolCall.id, "browser", 1));
        emit(new ToolCallEvent("browser", args, toolCall.id, "browser"));

        const stepStart = Date.now();

        try {
          // Check if code calls a projected gate (simple pattern matching)
          const gateResult = await tryProjectedGate(code, projectedGates);
          if (gateResult !== undefined) {
            if (gateResult.done) {
              const completionMsg: ToolMessage = {
                role: "tool",
                tool_call_id: toolCall.id,
                tool_name: "browser",
                content: `Task completed: ${gateResult.value}`,
                is_error: false,
              } as ToolMessage;
              messages.push(completionMsg);

              emit(
                new ToolResultEvent(
                  "browser",
                  `Task completed: ${gateResult.value}`,
                  toolCall.id,
                  false,
                ),
              );
              emit(new FinalResponseEvent(gateResult.value));

              gate_calls.push({
                gate_name: "browser",
                arguments: toolCall.function.arguments ?? "{}",
                result: `Task completed: ${gateResult.value}`,
                is_error: false,
              });

              return { messages, gate_calls, done: gateResult.value };
            }
          }

          const result = await ctx.evalCode(code, {
            timeoutMs: args.timeout_ms,
          });

          if (!result.ok) {
            const errorResult = truncateOutput(
              `Error: ${result.error}`,
              maxChars,
            );

            const errorMsg: ToolMessage = {
              role: "tool",
              tool_call_id: toolCall.id,
              tool_name: "browser",
              content: errorResult,
              is_error: true,
            } as ToolMessage;
            messages.push(errorMsg);
            if (options.on_tool_result) options.on_tool_result(errorMsg);

            emit(
              new ToolResultEvent("browser", errorResult, toolCall.id, true),
            );
            emit(
              new StepCompleteEvent(
                toolCall.id,
                "error",
                Date.now() - stepStart,
              ),
            );

            gate_calls.push({
              gate_name: "browser",
              arguments: toolCall.function.arguments ?? "{}",
              result: errorResult,
              is_error: true,
            });
          } else {
            const output = truncateOutput(result.output, maxChars);

            const successMsg: ToolMessage = {
              role: "tool",
              tool_call_id: toolCall.id,
              tool_name: "browser",
              content: output,
              is_error: false,
            } as ToolMessage;
            messages.push(successMsg);
            if (options.on_tool_result) options.on_tool_result(successMsg);

            emit(
              new ToolResultEvent("browser", output, toolCall.id, false),
            );
            emit(
              new StepCompleteEvent(
                toolCall.id,
                "completed",
                Date.now() - stepStart,
              ),
            );

            gate_calls.push({
              gate_name: "browser",
              arguments: toolCall.function.arguments ?? "{}",
              result: output,
              is_error: false,
            });
          }
        } catch (e: any) {
          if (e instanceof TaskComplete) {
            const completionMsg: ToolMessage = {
              role: "tool",
              tool_call_id: toolCall.id,
              tool_name: "browser",
              content: `Task completed: ${e.message}`,
              is_error: false,
            } as ToolMessage;
            messages.push(completionMsg);

            emit(
              new ToolResultEvent(
                "browser",
                `Task completed: ${e.message}`,
                toolCall.id,
                false,
              ),
            );
            emit(new FinalResponseEvent(e.message));

            gate_calls.push({
              gate_name: "browser",
              arguments: toolCall.function.arguments ?? "{}",
              result: `Task completed: ${e.message}`,
              is_error: false,
            });

            return { messages, gate_calls, done: e.message };
          }

          const errorResult = truncateOutput(
            `Error: ${String(e?.message ?? e)}`,
            maxChars,
          );

          const errorMsg: ToolMessage = {
            role: "tool",
            tool_call_id: toolCall.id,
            tool_name: "browser",
            content: errorResult,
            is_error: true,
          } as ToolMessage;
          messages.push(errorMsg);
          if (options.on_tool_result) options.on_tool_result(errorMsg);

          emit(
            new ToolResultEvent("browser", errorResult, toolCall.id, true),
          );
          emit(
            new StepCompleteEvent(
              toolCall.id,
              "error",
              Date.now() - stepStart,
            ),
          );

          gate_calls.push({
            gate_name: "browser",
            arguments: toolCall.function.arguments ?? "{}",
            result: errorResult,
            is_error: true,
          });
        }
      }

      return { messages, gate_calls };
    },

    async dispose() {
      if (ctx) {
        await ctx.dispose();
        ctx = null;
        initialized = false;
        projectedGates = [];
      }
    },
  };

  return medium;
}

/**
 * Try to match a submit_answer() call in the code.
 * Returns { done: true, value } if matched, undefined otherwise.
 */
async function tryProjectedGate(
  code: string,
  _gates: GateResult[],
): Promise<{ done: true; value: string } | undefined> {
  // Match submit_answer("value") or submit_answer('value') patterns
  const match = code
    .trim()
    .match(
      /^submit_answer\(\s*(?:"([^"]*)"|'([^']*)'|`([^`]*)`|([\w.]+))\s*\)$/,
    );
  if (match) {
    const value = match[1] ?? match[2] ?? match[3] ?? match[4] ?? "";
    return { done: true, value };
  }
  return undefined;
}

function truncateOutput(output: string, maxChars: number): string {
  if (output.length <= maxChars) return output;

  const lastNewline = output.lastIndexOf("\n", maxChars);
  const cutoff = lastNewline > maxChars / 2 ? lastNewline : maxChars;
  return (
    output.substring(0, cutoff) +
    `\n\n... [output truncated at ${maxChars} chars]`
  );
}
