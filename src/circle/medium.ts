import type { ToolChoice, GateDefinition } from "../crystal/crystal";
import type { AssistantMessage, ToolMessage } from "../crystal/messages";
import type { BoundGate } from "./gate/gate";
import type { DependencyOverrides } from "./gate/depends";
import type { TurnEvent } from "../entity/events";
import type { CircleExecuteResult } from "./circle";

/**
 * A Medium is the substrate an entity works IN.
 *
 * No medium (tool-calling): crystal sees one tool per gate, execute() dispatches tool_calls to gates by name.
 * JS medium: crystal sees one `js` tool with tool_choice: "required", execute() runs code in a QuickJS sandbox.
 * Gates are projected into the medium as host functions.
 */
export interface Medium {
  /** Initialize the medium — create sandbox, project gates as host functions. */
  init(
    gates: BoundGate[],
    dependency_overrides?: DependencyOverrides | null,
  ): Promise<void>;

  /** What the crystal sees when this medium is active. */
  crystalView(): {
    tool_definitions: GateDefinition[];
    tool_choice: ToolChoice;
  };

  /** Execute the entity's output in this medium. */
  execute(
    utterance: AssistantMessage,
    options: {
      on_event?: (event: TurnEvent) => void;
      on_tool_result?: (msg: ToolMessage) => void;
    },
  ): Promise<CircleExecuteResult>;

  /** Tear down the medium. */
  dispose(): Promise<void>;
}
