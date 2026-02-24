import type { ToolChoice, GateDefinition } from "../../crystal/crystal";
import type { AssistantMessage, ToolMessage } from "../../crystal/messages";
import type { BoundGate } from "../gate/gate";
import type { DependencyOverrides } from "../gate/depends";
import type { TurnEvent } from "../../entity/events";
import type { CircleExecuteResult } from "../circle";
import type { Medium } from "../medium";
import { exec } from "child_process";
import { promisify } from "util";
import { TaskComplete } from "../../entity/errors";
import {
  StepStartEvent,
  StepCompleteEvent,
  ToolCallEvent,
  ToolResultEvent,
  FinalResponseEvent,
} from "../../entity/events";

const execAsync = promisify(exec);

export type BashMediumOptions = {
  /** Working directory for commands (default: process.cwd()). */
  cwd?: string;
  /** Default command timeout in ms (default: 30000). */
  defaultTimeoutMs?: number;
  /** Max output characters (default: 9000). */
  maxOutputChars?: number;
  /** Max command length (default: 5000). */
  maxCommandLength?: number;
};

/**
 * Creates a bash medium — a shell session that the entity works in.
 *
 * Gates are described in the system prompt but not projected into the shell.
 * The crystal sees a single `bash` tool with tool_choice: "required".
 * Termination is via the submit_answer command pattern.
 */
export function bash(opts?: BashMediumOptions): Medium {
  let initialized = false;
  let projectedGates: BoundGate[] = [];

  const cwd = opts?.cwd ?? process.cwd();
  const defaultTimeout = opts?.defaultTimeoutMs ?? 30_000;
  const maxChars = opts?.maxOutputChars ?? 9000;
  const maxCommandLen = opts?.maxCommandLength ?? 5000;

  const bashToolDefinition: GateDefinition = {
    name: "bash",
    description:
      "Execute a shell command and return output. Use submit_answer 'value' to return your final result.",
    parameters: {
      type: "object",
      properties: {
        command: {
          type: "string",
          description: "Shell command to execute.",
          maxLength: maxCommandLen,
        },
        timeout: {
          type: "integer",
          description: "Command timeout in milliseconds.",
        },
      },
      required: ["command"],
      additionalProperties: false,
    },
  };

  const medium: Medium = {
    async init(
      gates: BoundGate[],
      _dependency_overrides?: DependencyOverrides | null,
    ) {
      if (initialized) return;
      projectedGates = gates;
      initialized = true;
    },

    crystalView(): {
      tool_definitions: GateDefinition[];
      tool_choice: ToolChoice;
    } {
      return {
        tool_definitions: [bashToolDefinition],
        tool_choice: { type: "tool", name: "bash" },
      };
    },

    async execute(
      utterance: AssistantMessage,
      options: {
        on_event?: (event: TurnEvent) => void;
        on_tool_result?: (msg: ToolMessage) => void;
      },
    ): Promise<CircleExecuteResult> {
      if (!initialized) {
        throw new Error(
          "Bash medium not initialized — call init() first",
        );
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

        const command = args.command ?? args._raw ?? "";

        emit(new StepStartEvent(toolCall.id, "bash", 1));
        emit(new ToolCallEvent("bash", args, toolCall.id, "bash"));

        const stepStart = Date.now();

        // Check for submit_answer pattern
        const submitMatch = command
          .trim()
          .match(/^submit_answer\s+(.+)$/s);
        if (submitMatch) {
          const answer = submitMatch[1].trim().replace(/^['"]|['"]$/g, "");

          const completionMsg: ToolMessage = {
            role: "tool",
            tool_call_id: toolCall.id,
            tool_name: "bash",
            content: `Task completed: ${answer}`,
            is_error: false,
          } as ToolMessage;
          messages.push(completionMsg);

          emit(
            new ToolResultEvent(
              "bash",
              `Task completed: ${answer}`,
              toolCall.id,
              false,
            ),
          );
          emit(new FinalResponseEvent(answer));

          gate_calls.push({
            gate_name: "bash",
            arguments: toolCall.function.arguments ?? "{}",
            result: `Task completed: ${answer}`,
            is_error: false,
          });

          return { messages, gate_calls, done: answer };
        }

        // Validate command length
        if (command.length > maxCommandLen) {
          const errorResult = `Error: Command too long (${command.length} chars). Maximum ${maxCommandLen}.`;

          const errorMsg: ToolMessage = {
            role: "tool",
            tool_call_id: toolCall.id,
            tool_name: "bash",
            content: errorResult,
            is_error: true,
          } as ToolMessage;
          messages.push(errorMsg);
          if (options.on_tool_result) options.on_tool_result(errorMsg);

          emit(
            new ToolResultEvent("bash", errorResult, toolCall.id, true),
          );
          emit(
            new StepCompleteEvent(
              toolCall.id,
              "error",
              Date.now() - stepStart,
            ),
          );

          gate_calls.push({
            gate_name: "bash",
            arguments: toolCall.function.arguments ?? "{}",
            result: errorResult,
            is_error: true,
          });
          continue;
        }

        try {
          const { stdout, stderr } = await execAsync(command, {
            cwd,
            timeout: args.timeout ?? defaultTimeout,
          });
          let output = `${stdout}${stderr}`.trim();

          if (!output) output = "(no output)";

          output = truncateOutput(output, maxChars);

          const successMsg: ToolMessage = {
            role: "tool",
            tool_call_id: toolCall.id,
            tool_name: "bash",
            content: output,
            is_error: false,
          } as ToolMessage;
          messages.push(successMsg);
          if (options.on_tool_result) options.on_tool_result(successMsg);

          emit(
            new ToolResultEvent("bash", output, toolCall.id, false),
          );
          emit(
            new StepCompleteEvent(
              toolCall.id,
              "completed",
              Date.now() - stepStart,
            ),
          );

          gate_calls.push({
            gate_name: "bash",
            arguments: toolCall.function.arguments ?? "{}",
            result: output,
            is_error: false,
          });
        } catch (e: any) {
          if (e instanceof TaskComplete) {
            const completionMsg: ToolMessage = {
              role: "tool",
              tool_call_id: toolCall.id,
              tool_name: "bash",
              content: `Task completed: ${e.message}`,
              is_error: false,
            } as ToolMessage;
            messages.push(completionMsg);

            emit(
              new ToolResultEvent(
                "bash",
                `Task completed: ${e.message}`,
                toolCall.id,
                false,
              ),
            );
            emit(new FinalResponseEvent(e.message));

            gate_calls.push({
              gate_name: "bash",
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
            tool_name: "bash",
            content: errorResult,
            is_error: true,
          } as ToolMessage;
          messages.push(errorMsg);
          if (options.on_tool_result) options.on_tool_result(errorMsg);

          emit(
            new ToolResultEvent("bash", errorResult, toolCall.id, true),
          );
          emit(
            new StepCompleteEvent(
              toolCall.id,
              "error",
              Date.now() - stepStart,
            ),
          );

          gate_calls.push({
            gate_name: "bash",
            arguments: toolCall.function.arguments ?? "{}",
            result: errorResult,
            is_error: true,
          });
        }
      }

      return { messages, gate_calls };
    },

    async dispose() {
      initialized = false;
      projectedGates = [];
    },

    capabilityDocs(): string {
      return [
        "### SHELL PHYSICS (bash)",
        `1. Each command runs in a fresh subprocess (cwd: ${cwd}). Shell state (variables, cd) resets between commands. Filesystem changes persist.`,
        "2. Use `submit_answer <value>` as a command to return your final result.",
        `3. stdout and stderr are combined in output (truncated at ${maxChars} chars).`,
      ].join("\n");
    },
  };

  return medium;
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
