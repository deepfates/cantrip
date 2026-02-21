import type { GateDefinition } from "../../crystal/crystal";
import type { DependencyOverrides } from "./depends";
import type { GateContent } from "./decorator";

/** Documentation metadata a gate carries for compositional prompt generation. */
export type GateDocs = {
  /** Name to use when presenting this gate in a sandbox (e.g., "call_entity" for the delegation gate) */
  sandbox_name?: string;
  /** Function signature for documentation (e.g., "call_entity(intent: string): string") */
  signature?: string;
  /** Human-readable description of what this gate does */
  description?: string;
  /** Code examples showing usage */
  examples?: string[];
  /** Which section of the prompt this belongs to (e.g., "HOST FUNCTIONS") */
  section?: string;
};

export type BoundGate = {
  name: string;
  definition: GateDefinition;
  execute(args: Record<string, any>, overrides?: DependencyOverrides): Promise<GateContent>;
  ephemeral: number | boolean;
  /** Optional documentation metadata for prompt generation */
  docs?: GateDocs;
};
