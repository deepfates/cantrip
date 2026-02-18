import type { GateDefinition } from "../../crystal/crystal";
import type { DependencyOverrides } from "./depends";
import type { GateContent } from "./decorator";

export type GateResult = {
  name: string;
  definition: GateDefinition;
  execute(args: Record<string, any>, overrides?: DependencyOverrides): Promise<GateContent>;
  ephemeral: number | boolean;
};
