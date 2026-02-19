import type { ToolChoice, GateDefinition } from "../crystal/crystal";
import type { AssistantMessage, ToolMessage } from "../crystal/messages";
import { extractToolMessageText } from "../crystal/messages";
import type { GateResult } from "./gate/gate";
import type { DependencyOverrides } from "./gate/depends";
import type { Ward } from "./ward";
import { resolveWards } from "./ward";
import type { TurnEvent } from "../entity/events";
import {
  StepStartEvent,
  StepCompleteEvent,
  ToolCallEvent,
  ToolResultEvent,
  FinalResponseEvent,
} from "../entity/events";
import { TaskComplete } from "../entity/errors";
import { executeToolCall, extractScreenshot } from "../entity/runtime";
import type { Medium } from "./medium";
import { done_for_medium } from "./gate/builtin/done";

/** A gate call record produced by circle.execute(). */
export type CircleGateCall = {
  gate_name: string;
  arguments: string;
  result: string;
  is_error: boolean;
};

/** Result of circle.execute(). */
export type CircleExecuteResult = {
  messages: ToolMessage[];
  gate_calls: CircleGateCall[];
  done?: string;
};

/**
 * A Circle binds a set of Gates (tools) together with Wards (constraints).
 *
 * It represents the "capability envelope" of an Entity — what actions
 * it can take and what limits govern those actions.
 *
 * As an execution interface, it also owns tool dispatch: given the entity's
 * output (an AssistantMessage with tool_calls), the circle executes gate
 * calls and returns observation messages.
 */
export interface Circle {
  /** The gates (tools) available within this circle. */
  gates: GateResult[];

  /** The wards (constraints) that govern execution within this circle. */
  wards: Ward[];

  /** True when the circle has a medium that handles termination (e.g., submit_answer in JS). */
  hasMedium?: boolean;

  /** What the crystal needs to see — tool definitions and tool_choice. */
  crystalView(toolChoice?: ToolChoice): {
    tool_definitions: GateDefinition[];
    tool_choice: ToolChoice;
  };

  /** Execute the entity's output. Returns observation messages to append. */
  execute(
    utterance: AssistantMessage,
    options: {
      dependency_overrides?: DependencyOverrides | null;
      on_event?: (event: TurnEvent) => void;
      on_tool_result?: (msg: ToolMessage) => void;
    },
  ): Promise<CircleExecuteResult>;

  /** Optional cleanup. */
  dispose?(): Promise<void>;
}

/**
 * Construct a Circle with validation.
 *
 * CIRCLE-1: Must have a gate named "done" (relaxed when medium is present — the medium handles termination).
 * CIRCLE-2: Must have at least one ward with max_turns > 0.
 *
 * When no medium: returns a ToolCallingCircle that dispatches tool_calls to gates.
 * When medium present: delegates crystalView/execute/dispose to the medium.
 */
export function Circle(opts: { medium?: Medium; gates?: GateResult[]; wards: Ward[] }): Circle {
  const gates = opts.gates ?? [];
  const hasMedium = !!opts.medium;

  // Auto-inject done_for_medium when medium is present and no done gate provided
  if (hasMedium && !gates.some((g) => g.name === "done")) {
    gates.push(done_for_medium());
  }

  // CIRCLE-1: done gate required unless medium handles termination
  if (!hasMedium && !gates.some((g) => g.name === "done")) {
    throw new Error("Circle must have a done gate");
  }
  if (opts.wards.length === 0) {
    throw new Error("Circle must have at least one ward");
  }
  const resolved = resolveWards(opts.wards);
  if (!isFinite(resolved.max_turns)) {
    throw new Error("Circle wards must resolve to finite max_turns (CIRCLE-2)");
  }

  // When medium is present, delegate to it
  if (opts.medium) {
    const medium = opts.medium;
    let initPromise: Promise<void> | null = null;

    return {
      gates,
      wards: opts.wards,
      hasMedium: true,

      crystalView(_toolChoice?: ToolChoice) {
        return medium.crystalView();
      },

      async execute(utterance, options) {
        // Lazy init on first execute
        if (!initPromise) {
          initPromise = medium.init(gates, options.dependency_overrides);
        }
        await initPromise;

        return medium.execute(utterance, {
          on_event: options.on_event,
          on_tool_result: options.on_tool_result,
        });
      },

      async dispose() {
        if (initPromise) {
          await initPromise;
        }
        await medium.dispose();
      },
    };
  }

  // No medium: tool-calling circle (original behavior)

  // Build tool_map once
  const tool_map = new Map<string, GateResult>();
  for (const gate of gates) {
    tool_map.set(gate.name, gate);
  }

  // Build tool_definitions once
  const tool_definitions: GateDefinition[] = gates.map(
    (g) => g.definition,
  );

  return {
    gates,
    wards: opts.wards,

    crystalView(toolChoice?: ToolChoice) {
      return {
        tool_definitions,
        tool_choice: toolChoice ?? "auto",
      };
    },

    async execute(utterance, options) {
      const {
        dependency_overrides,
        on_event,
        on_tool_result,
      } = options;
      const emit = on_event ?? (() => {});

      const messages: ToolMessage[] = [];
      const gate_calls: CircleGateCall[] = [];
      const observationParts: string[] = [];

      let stepNumber = 0;
      for (const toolCall of utterance.tool_calls ?? []) {
        stepNumber += 1;
        let args: Record<string, any> = {};
        try {
          args = JSON.parse(toolCall.function.arguments ?? "{}");
        } catch {
          args = { _raw: toolCall.function.arguments };
        }

        emit(
          new StepStartEvent(toolCall.id, toolCall.function.name, stepNumber),
        );
        emit(
          new ToolCallEvent(
            toolCall.function.name,
            args,
            toolCall.id,
            toolCall.function.name,
          ),
        );

        const stepStart = Date.now();
        try {
          const toolResult = await executeToolCall({
            tool_call: toolCall,
            tool_map,
            dependency_overrides,
          });
          messages.push(toolResult);
          if (on_tool_result) on_tool_result(toolResult);

          const resultText =
            typeof toolResult.content === "string"
              ? toolResult.content
              : JSON.stringify(toolResult.content);

          emit(
            new ToolResultEvent(
              toolCall.function.name,
              extractToolMessageText(toolResult),
              toolCall.id,
              toolResult.is_error ?? false,
              extractScreenshot(toolResult),
            ),
          );
          emit(
            new StepCompleteEvent(
              toolCall.id,
              toolResult.is_error ? "error" : "completed",
              Date.now() - stepStart,
            ),
          );

          gate_calls.push({
            gate_name: toolCall.function.name,
            arguments: toolCall.function.arguments ?? "{}",
            result: resultText,
            is_error: toolResult.is_error ?? false,
          });
          observationParts.push(resultText);
        } catch (err) {
          if (err instanceof TaskComplete) {
            const completionMsg: ToolMessage = {
              role: "tool",
              tool_call_id: toolCall.id,
              tool_name: toolCall.function.name,
              content: `Task completed: ${err.message}`,
              is_error: false,
            } as ToolMessage;
            messages.push(completionMsg);

            emit(
              new ToolResultEvent(
                toolCall.function.name,
                `Task completed: ${err.message}`,
                toolCall.id,
                false,
              ),
            );
            emit(new FinalResponseEvent(err.message));

            gate_calls.push({
              gate_name: toolCall.function.name,
              arguments: toolCall.function.arguments ?? "{}",
              result: `Task completed: ${err.message}`,
              is_error: false,
            });

            return { messages, gate_calls, done: err.message };
          }
          throw err;
        }
      }

      return { messages, gate_calls };
    },
  };
}
