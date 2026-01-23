import type { ToolDefinition } from "../llm/base";
import type { DependencyOverrides } from "./depends";
import type { ToolContent } from "./decorator";

export type ToolLike = {
  name: string;
  definition: ToolDefinition;
  execute(args: Record<string, any>, overrides?: DependencyOverrides): Promise<ToolContent>;
  ephemeral: number | boolean;
};
