import type { ToolChoice, GateDefinition } from "../../crystal/crystal";
import type { AssistantMessage, ToolMessage } from "../../crystal/messages";
import type { BoundGate } from "../gate/gate";
import type { DependencyOverrides } from "../gate/depends";
import type { TurnEvent } from "../../entity/events";
import type { CircleExecuteResult } from "../circle";
import type { Medium } from "../medium";
import {
  JsAsyncContext,
  createAsyncModule,
} from "./js/async_context";
/**
 * Formats sandbox execution results into a compact metadata string.
 * This prevents the entity's prompt history from being flooded with large data dumps.
 */
export function formatSandboxMetadata(output: string): string {
  if (!output || output === "undefined") return "[Result: undefined]";
  const length = output.length;
  const preview = output.slice(0, 150).replace(/\n/g, " ");
  return `[Result: ${length} chars] "${preview}${length > 150 ? "..." : ""}"`;
}
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

/** Extract parameter names from a gate definition's JSON schema properties. */
function getParameterNames(definition: GateDefinition): string[] {
  const props = definition.parameters?.properties;
  if (!props || typeof props !== "object") return [];
  return Object.keys(props as Record<string, unknown>);
}

/** Produce a rich one-line description of a state entry for capabilityDocs(). */
function describeStateEntry(val: unknown): string {
  if (typeof val === "string") {
    const preview = val.slice(0, 100).replace(/\n/g, " ");
    return `string(${val.length} chars) — "${preview}${val.length > 100 ? "..." : ""}"`;
  }
  if (Array.isArray(val)) {
    const elemType = val.length > 0 ? typeof val[0] : "empty";
    let preview: string;
    try { preview = JSON.stringify(val.slice(0, 3)); } catch { preview = "[...]"; }
    if (preview.length > 200) preview = preview.slice(0, 200) + "...";
    return `Array(${val.length} items, ${elemType}) — ${preview}`;
  }
  if (typeof val === "object" && val !== null) {
    const keys = Object.keys(val);
    let preview: string;
    try { preview = JSON.stringify(val); } catch { preview = "{...}"; }
    if (preview.length > 200) preview = preview.slice(0, 200) + "...";
    return `Object{${keys.length} keys: ${keys.join(", ")}} — ${preview}`;
  }
  if (typeof val === "number" || typeof val === "boolean") {
    return `${typeof val}(${val})`;
  }
  return typeof val;
}

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
      required: ["code", "timeout_ms"],
      additionalProperties: false,
    },
  };

  const medium: Medium = {
    async init(gates: BoundGate[], dependency_overrides?: DependencyOverrides | null) {
      if (initialized) return;

      const module = await createAsyncModule();
      sandbox = await JsAsyncContext.create({ module });

      // Inject state as globals
      if (opts?.state) {
        for (const [key, value] of Object.entries(opts.state)) {
          sandbox.setGlobal(key, value);
        }
      }

      // Project gates as host functions in the sandbox
      // The done gate (with docs.sandbox_name: "submit_answer") is projected like any other gate.
      // dependency_overrides are captured and forwarded to gate.execute() for Depends resolution.
      const overrides = dependency_overrides ?? undefined;
      for (const gate of gates) {
        const sandboxName = gate.docs?.sandbox_name ?? gate.name;
        const paramNames = getParameterNames(gate.definition);

        sandbox.registerAsyncFunction(sandboxName, async (...args: unknown[]) => {
          // If a single plain object argument (not an array), pass it as the args map
          if (args.length === 1 && typeof args[0] === "object" && args[0] !== null && !Array.isArray(args[0])) {
            return await gate.execute(args[0] as Record<string, unknown>, overrides);
          }
          // Map positional args to named parameters from the gate definition
          if (paramNames.length > 0) {
            const argMap: Record<string, unknown> = {};
            for (let i = 0; i < args.length && i < paramNames.length; i++) {
              argMap[paramNames[i]] = args[i];
            }
            return await gate.execute(argMap, overrides);
          }
          return await gate.execute({ args }, overrides);
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
        on_event?: (event: TurnEvent) => void;
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
            const metadata = formatSandboxMetadata(result.output);

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

    capabilityDocs(): string {
      const lines: string[] = [
        "### SANDBOX PHYSICS (QuickJS)",
        "1. **BLOCKING ONLY**: All host functions are synchronous and blocking.",
        "2. **NO ASYNC/AWAIT**: Do NOT use `async`, `await`, or `Promise`. They will crash the sandbox.",
        "3. **PERSISTENCE**: Use `var` or `globalThis` to save state between `js` tool calls.",
        "- `console.log(...args)`: Prints output (truncated in results).",
      ];

      // Describe initial state if present
      if (opts?.state) {
        const keys = Object.keys(opts.state);
        if (keys.length > 0) {
          lines.push("");
          lines.push("### INITIAL STATE");
          lines.push("The following globals are pre-loaded in the sandbox:");
          for (const key of keys) {
            const val = opts.state[key];
            lines.push(`- \`${key}\`: ${describeStateEntry(val)}`);
          }
        }
      }

      return lines.join("\n");
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
