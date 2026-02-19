import type { ToolChoice, GateDefinition } from "../../crystal/crystal";
import type { AssistantMessage, ToolMessage } from "../../crystal/messages";
import type { GateResult } from "../gate/gate";
import type { DependencyOverrides } from "../gate/depends";
import type { AgentEvent } from "../../entity/events";
import type { CircleExecuteResult } from "../circle";
import type { Medium } from "../medium";
import {
  JsAsyncContext,
  createAsyncModule,
} from "../gate/builtin/js_async_context";
import { formatRlmMetadata } from "../gate/builtin/call_agent_tools";
import { TaskComplete } from "../../entity/errors";
import {
  StepStartEvent,
  StepCompleteEvent,
  ToolCallEvent,
  ToolResultEvent,
  FinalResponseEvent,
} from "../../entity/events";

export type JsMediumOptions = {
  /** Initial state to inject as globals into the sandbox. */
  state?: Record<string, unknown>;
};

/**
 * Creates a JS medium — a QuickJS sandbox that the entity works in.
 *
 * Gates are projected into the sandbox as host functions.
 * The crystal sees a single `js` tool with tool_choice: "required".
 * Termination is via `submit_answer()` which throws SIGNAL_FINAL.
 */
export function js(opts?: JsMediumOptions): Medium {
  let sandbox: JsAsyncContext | null = null;
  let initialized = false;

  const jsToolDefinition: GateDefinition = {
    name: "js",
    description:
      "Execute JavaScript in the persistent sandbox. Results are returned as metadata. You MUST use submit_answer() to return your final result.",
    parameters: {
      type: "object",
      properties: {
        code: { type: "string", description: "JavaScript code to execute." },
        timeout_ms: { type: "integer", description: "Optional execution timeout in milliseconds." },
      },
      required: ["code"],
      additionalProperties: false,
    },
  };

  const medium: Medium = {
    async init(gates: GateResult[], _dependency_overrides?: DependencyOverrides | null) {
      if (initialized) return;

      const module = await createAsyncModule();
      sandbox = await JsAsyncContext.create({ module });

      // Inject state as globals
      if (opts?.state) {
        for (const [key, value] of Object.entries(opts.state)) {
          sandbox.setGlobal(key, value);
        }
      }

      // submit_answer: the done gate — throws SIGNAL_FINAL to terminate
      sandbox.registerAsyncFunction("submit_answer", async (value) => {
        const result =
          typeof value === "string" ? value : JSON.stringify(value, null, 2);
        throw new Error(`SIGNAL_FINAL:${result}`);
      });

      // Project gates as host functions in the sandbox
      for (const gate of gates) {
        // Skip 'done' gate — submit_answer handles termination
        if (gate.name === "done") continue;

        sandbox.registerAsyncFunction(gate.name, async (...args: unknown[]) => {
          // If a single object argument, pass it as the args map
          const argMap =
            args.length === 1 && typeof args[0] === "object" && args[0] !== null
              ? (args[0] as Record<string, unknown>)
              : { args };
          const result = await gate.execute(argMap);
          return result;
        });
      }

      initialized = true;
    },

    crystalView(): { tool_definitions: GateDefinition[]; tool_choice: ToolChoice } {
      return {
        tool_definitions: [jsToolDefinition],
        tool_choice: { type: "tool", name: "js" },
      };
    },

    async execute(
      utterance: AssistantMessage,
      options: {
        on_event?: (event: AgentEvent) => void;
        on_tool_result?: (msg: ToolMessage) => void;
      },
    ): Promise<CircleExecuteResult> {
      if (!sandbox || !initialized) {
        throw new Error("JS medium not initialized — call init() first");
      }

      const emit = options.on_event ?? (() => {});
      const messages: ToolMessage[] = [];
      const gate_calls: CircleExecuteResult["gate_calls"] = [];

      // The crystal should emit a single tool_call for the `js` tool
      for (const toolCall of utterance.tool_calls ?? []) {
        let args: Record<string, any> = {};
        try {
          args = JSON.parse(toolCall.function.arguments ?? "{}");
        } catch {
          args = { _raw: toolCall.function.arguments };
        }

        const code = args.code ?? args._raw ?? "";

        emit(new StepStartEvent(toolCall.id, "js", 1));
        emit(new ToolCallEvent("js", args, toolCall.id, "js"));

        const stepStart = Date.now();

        try {
          const result = await sandbox.evalCode(code, {
            executionTimeoutMs: args.timeout_ms,
          });

          if (!result.ok) {
            // Handle the SIGNAL_FINAL termination
            if (result.error.startsWith("SIGNAL_FINAL:")) {
              const answer = result.error.replace("SIGNAL_FINAL:", "");

              const completionMsg: ToolMessage = {
                role: "tool",
                tool_call_id: toolCall.id,
                tool_name: "js",
                content: `Task completed: ${answer}`,
                is_error: false,
              } as ToolMessage;
              messages.push(completionMsg);

              emit(new ToolResultEvent("js", `Task completed: ${answer}`, toolCall.id, false));
              emit(new FinalResponseEvent(answer));

              gate_calls.push({
                gate_name: "js",
                arguments: toolCall.function.arguments ?? "{}",
                result: `Task completed: ${answer}`,
                is_error: false,
              });

              return { messages, gate_calls, done: answer };
            }

            // Non-fatal error — return as error observation
            let error = result.error;
            if (error.includes("Lifetime not alive")) {
              error +=
                " (Note: All sandbox functions are blocking. Do NOT use async/await, async functions, or Promises.)";
            }
            const errorResult = `Error: ${error}`;

            const errorMsg: ToolMessage = {
              role: "tool",
              tool_call_id: toolCall.id,
              tool_name: "js",
              content: errorResult,
              is_error: true,
            } as ToolMessage;
            messages.push(errorMsg);
            if (options.on_tool_result) options.on_tool_result(errorMsg);

            emit(new ToolResultEvent("js", errorResult, toolCall.id, true));
            emit(new StepCompleteEvent(toolCall.id, "error", Date.now() - stepStart));

            gate_calls.push({
              gate_name: "js",
              arguments: toolCall.function.arguments ?? "{}",
              result: errorResult,
              is_error: true,
            });
          } else {
            // Success — format as metadata
            const metadata = formatRlmMetadata(result.output);

            const successMsg: ToolMessage = {
              role: "tool",
              tool_call_id: toolCall.id,
              tool_name: "js",
              content: metadata,
              is_error: false,
            } as ToolMessage;
            messages.push(successMsg);
            if (options.on_tool_result) options.on_tool_result(successMsg);

            emit(new ToolResultEvent("js", metadata, toolCall.id, false));
            emit(new StepCompleteEvent(toolCall.id, "completed", Date.now() - stepStart));

            gate_calls.push({
              gate_name: "js",
              arguments: toolCall.function.arguments ?? "{}",
              result: metadata,
              is_error: false,
            });
          }
        } catch (e: any) {
          if (e instanceof TaskComplete) {
            const completionMsg: ToolMessage = {
              role: "tool",
              tool_call_id: toolCall.id,
              tool_name: "js",
              content: `Task completed: ${e.message}`,
              is_error: false,
            } as ToolMessage;
            messages.push(completionMsg);

            emit(new ToolResultEvent("js", `Task completed: ${e.message}`, toolCall.id, false));
            emit(new FinalResponseEvent(e.message));

            gate_calls.push({
              gate_name: "js",
              arguments: toolCall.function.arguments ?? "{}",
              result: `Task completed: ${e.message}`,
              is_error: false,
            });

            return { messages, gate_calls, done: e.message };
          }

          let msg = String(e?.message ?? e);
          if (msg.includes("Lifetime not alive")) {
            msg +=
              " (Note: All sandbox functions are blocking. Do NOT use async/await, async functions, or Promises.)";
          }
          const errorResult = `Error: ${msg}`;

          const errorMsg: ToolMessage = {
            role: "tool",
            tool_call_id: toolCall.id,
            tool_name: "js",
            content: errorResult,
            is_error: true,
          } as ToolMessage;
          messages.push(errorMsg);
          if (options.on_tool_result) options.on_tool_result(errorMsg);

          emit(new ToolResultEvent("js", errorResult, toolCall.id, true));
          emit(new StepCompleteEvent(toolCall.id, "error", Date.now() - stepStart));

          gate_calls.push({
            gate_name: "js",
            arguments: toolCall.function.arguments ?? "{}",
            result: errorResult,
            is_error: true,
          });
        }
      }

      return { messages, gate_calls };
    },

    async dispose() {
      if (sandbox) {
        sandbox.dispose();
        sandbox = null;
        initialized = false;
      }
    },
  };

  // Expose sandbox for advanced use cases (e.g., registering additional host functions)
  Object.defineProperty(medium, "sandbox", {
    get() {
      return sandbox;
    },
    enumerable: false,
  });

  return medium;
}

/** Type-safe accessor for the sandbox on a JS medium (for advanced use). */
export function getJsMediumSandbox(medium: Medium): JsAsyncContext | null {
  return (medium as any).sandbox ?? null;
}
