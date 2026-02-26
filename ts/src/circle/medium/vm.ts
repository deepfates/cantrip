import * as nodeVm from "node:vm";
import type { ToolChoice, GateDefinition } from "../../crystal/crystal";
import type { AssistantMessage, ToolMessage } from "../../crystal/messages";
import type { BoundGate } from "../gate/gate";
import type { DependencyOverrides } from "../gate/depends";
import type { TurnEvent } from "../../entity/events";
import type { CircleExecuteResult } from "../circle";
import type { Medium } from "../medium";
import { formatSandboxMetadata } from "./js";
import { TaskComplete } from "../../entity/errors";
import {
  StepStartEvent,
  StepCompleteEvent,
  ToolCallEvent,
  ToolResultEvent,
  FinalResponseEvent,
} from "../../entity/events";

export type VmMediumOptions = {
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
 * Creates a vm medium — a node:vm sandbox that the entity works in.
 *
 * Gates are projected into the sandbox as async functions callable via await.
 * The crystal sees a single `vm` tool with tool_choice: "required".
 * Full ES2024 support — arrow functions, async/await, native objects.
 * Weak isolation (V8 context, not a security boundary).
 */
export function vm(opts?: VmMediumOptions): Medium {
  let context: nodeVm.Context | null = null;
  let initialized = false;

  const vmToolDefinition: GateDefinition = {
    name: "vm",
    description:
      "Execute JavaScript in the persistent sandbox. Results are returned as metadata. You MUST use `await submit_answer(result)` to return your final result.",
    parameters: {
      type: "object",
      properties: {
        code: { type: "string", description: "JavaScript code to execute. Async/await is supported." },
        timeout_ms: { type: "integer", description: "Execution timeout in milliseconds. Use 0 for no timeout." },
      },
      required: ["code"],
      additionalProperties: false,
    },
  };

  // Console output buffer — accumulates across a single execute() call
  let consoleBuffer: string[] = [];

  const medium: Medium = {
    async init(gates: BoundGate[], dependency_overrides?: DependencyOverrides | null) {
      if (initialized) return;

      // Create a V8 context with safe builtins
      const sandbox: Record<string, unknown> = {
        console: {
          log: (...args: unknown[]) => {
            consoleBuffer.push(args.map(a => typeof a === "string" ? a : JSON.stringify(a)).join(" "));
          },
          error: (...args: unknown[]) => {
            consoleBuffer.push("[ERROR] " + args.map(a => typeof a === "string" ? a : JSON.stringify(a)).join(" "));
          },
          warn: (...args: unknown[]) => {
            consoleBuffer.push("[WARN] " + args.map(a => typeof a === "string" ? a : JSON.stringify(a)).join(" "));
          },
        },
        setTimeout: undefined,
        setInterval: undefined,
        globalThis: undefined as unknown, // will be set to the context itself
      };

      context = nodeVm.createContext(sandbox);
      // Make globalThis point to the context
      nodeVm.runInContext("globalThis = this;", context);

      // Inject state as globals
      if (opts?.state) {
        for (const [key, value] of Object.entries(opts.state)) {
          context[key] = value;
        }
      }

      // Project gates as async functions in the context
      const overrides = dependency_overrides ?? undefined;
      for (const gate of gates) {
        const sandboxName = gate.docs?.sandbox_name ?? gate.name;
        const paramNames = getParameterNames(gate.definition);

        const exec = (a: Record<string, unknown>) => gate.execute(a, overrides);

        context[sandboxName] = async (...args: unknown[]) => {
          // Single plain object arg → pass directly as args map
          if (args.length === 1 && typeof args[0] === "object" && args[0] !== null && !Array.isArray(args[0])) {
            return await exec(args[0] as Record<string, unknown>);
          }
          // Positional args → map to named parameters from gate definition
          if (paramNames.length > 0) {
            const argMap: Record<string, unknown> = {};
            for (let i = 0; i < args.length && i < paramNames.length; i++) {
              argMap[paramNames[i]] = args[i];
            }
            return await exec(argMap);
          }
          return await exec({ args });
        };
      }

      initialized = true;
    },

    crystalView(): { tool_definitions: GateDefinition[]; tool_choice: ToolChoice } {
      return {
        tool_definitions: [vmToolDefinition],
        tool_choice: { type: "tool", name: "vm" },
      };
    },

    async execute(
      utterance: AssistantMessage,
      options: {
        on_event?: (event: TurnEvent) => void;
        on_tool_result?: (msg: ToolMessage) => void;
      },
    ): Promise<CircleExecuteResult> {
      if (!context || !initialized) {
        throw new Error("VM medium not initialized — call init() first");
      }

      const emit = options.on_event ?? (() => {});
      const messages: ToolMessage[] = [];
      const gate_calls: CircleExecuteResult["gate_calls"] = [];

      for (const toolCall of utterance.tool_calls ?? []) {
        let args: Record<string, any> = {};
        try {
          args = JSON.parse(toolCall.function.arguments ?? "{}");
        } catch {
          args = { _raw: toolCall.function.arguments };
        }

        const code = args.code ?? args._raw ?? "";
        const timeoutMs = args.timeout_ms || undefined;

        emit(new StepStartEvent(toolCall.id, "vm", 1));
        emit(new ToolCallEvent("vm", args, toolCall.id, "vm"));

        const stepStart = Date.now();
        consoleBuffer = [];

        try {
          // Two paths depending on whether code uses `await`:
          //
          // NO AWAIT: runInContext directly. `var` persists at context level,
          //   last expression value is returned (like eval).
          //
          // HAS AWAIT: wrap in async IIFE. `await` works, but `var` is scoped
          //   to the IIFE (doesn't persist). Entity uses `globalThis` for
          //   persistence (capabilityDocs teaches this). Last expression value
          //   is not captured — data lives in variables, not return values.
          const hasAwait = /\bawait\b/.test(code);
          let result: unknown;

          if (hasAwait) {
            const wrapped = `(async () => {\n${code}\n})()`;
            result = nodeVm.runInContext(wrapped, context, {
              timeout: timeoutMs,
              breakOnSigint: true,
            });
            // Async IIFE returns a Promise — await it
            if (result && typeof (result as any).then === "function") {
              result = await result;
            }
          } else {
            result = nodeVm.runInContext(code, context, {
              timeout: timeoutMs,
              breakOnSigint: true,
            });
          }

          // Build output from console buffer + return value
          const resultStr = result !== undefined ? String(result) : undefined;
          const parts: string[] = [];
          if (consoleBuffer.length > 0) parts.push(consoleBuffer.join("\n"));
          if (resultStr && resultStr !== "undefined") parts.push(resultStr);
          const output = parts.join("\n") || "undefined";

          const metadata = formatSandboxMetadata(output);

          const successMsg: ToolMessage = {
            role: "tool",
            tool_call_id: toolCall.id,
            tool_name: "vm",
            content: metadata,
            is_error: false,
          } as ToolMessage;
          messages.push(successMsg);
          if (options.on_tool_result) options.on_tool_result(successMsg);

          emit(new ToolResultEvent("vm", metadata, toolCall.id, false));
          emit(new StepCompleteEvent(toolCall.id, "completed", Date.now() - stepStart));

          gate_calls.push({
            gate_name: "vm",
            arguments: toolCall.function.arguments ?? "{}",
            result: metadata,
            is_error: false,
          });
        } catch (e: any) {
          // Check for the SIGNAL_FINAL sentinel from done_for_medium gate
          const msg = String(e?.message ?? e);
          if (msg.includes("SIGNAL_FINAL:")) {
            const answer = msg.replace(/.*SIGNAL_FINAL:/, "");

            const completionMsg: ToolMessage = {
              role: "tool",
              tool_call_id: toolCall.id,
              tool_name: "vm",
              content: `Task completed: ${answer}`,
              is_error: false,
            } as ToolMessage;
            messages.push(completionMsg);

            emit(new ToolResultEvent("vm", `Task completed: ${answer}`, toolCall.id, false));
            emit(new FinalResponseEvent(answer));

            gate_calls.push({
              gate_name: "vm",
              arguments: toolCall.function.arguments ?? "{}",
              result: `Task completed: ${answer}`,
              is_error: false,
            });

            return { messages, gate_calls, done: answer };
          }

          // Non-fatal error
          const errorResult = msg.match(/^[A-Z][A-Za-z]*Error\b/)
            ? msg
            : `Error: ${msg}`;

          const errorMsg: ToolMessage = {
            role: "tool",
            tool_call_id: toolCall.id,
            tool_name: "vm",
            content: errorResult,
            is_error: true,
          } as ToolMessage;
          messages.push(errorMsg);
          if (options.on_tool_result) options.on_tool_result(errorMsg);

          emit(new ToolResultEvent("vm", errorResult, toolCall.id, true));
          emit(new StepCompleteEvent(toolCall.id, "error", Date.now() - stepStart));

          gate_calls.push({
            gate_name: "vm",
            arguments: toolCall.function.arguments ?? "{}",
            result: errorResult,
            is_error: true,
          });
        }
      }

      return { messages, gate_calls };
    },

    async dispose() {
      context = null;
      initialized = false;
      consoleBuffer = [];
    },

    capabilityDocs(): string {
      const lines: string[] = [
        "### SANDBOX PHYSICS (node:vm)",
        "1. **ASYNC SUPPORTED**: You can use `async`/`await`, arrow functions, and all ES2024 features.",
        "2. **PERSISTENCE**: Use `globalThis.x = value` to save state between calls. (`var` also works in sync code, but NOT when using `await`.)",
        "3. **GATE RESULTS**: Gate functions return strings. Use `JSON.parse()` for structured data.",
        "4. **GATES ARE ASYNC**: Call gates with `await`, e.g. `await repo_read('src/foo.ts')`.",
        "5. **RETURN VALUES**: The last expression value is shown in result metadata (sync code only). With `await`, use `console.log()` or `globalThis` to capture results.",
        "- `console.log(...args)`: Prints output (included in result metadata).",
      ];

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

  return medium;
}
