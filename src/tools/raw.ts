import type { ToolDefinition } from "../llm/base";
import type { DependencyOverrides } from "./depends";
import { Depends } from "./depends";
import { serializeToolResult, type ToolContent } from "./decorator";
import type { ToolLike } from "./types";

export type RawToolHandler<TArgs extends Record<string, any>, TResult> = (
  args: TArgs,
  deps: Record<string, any>,
) => Promise<TResult> | TResult;

export type RawToolOptions = {
  ephemeral?: number | boolean;
  dependencies?: Record<string, Depends<any>>;
};

export type RawToolDefinition = {
  name: string;
  description: string;
  parameters: ToolDefinition["parameters"];
  strict?: boolean;
};

export function rawTool<TArgs extends Record<string, any>>(
  definition: RawToolDefinition,
  handler: RawToolHandler<TArgs, any>,
  options?: RawToolOptions,
): ToolLike {
  const dependencies = options?.dependencies ?? {};
  return {
    name: definition.name,
    definition: {
      name: definition.name,
      description: definition.description,
      parameters: definition.parameters,
      strict: definition.strict ?? true,
    },
    ephemeral: options?.ephemeral ?? false,
    async execute(args: TArgs, overrides?: DependencyOverrides): Promise<ToolContent> {
      const resolvedDeps: Record<string, any> = {};
      for (const [name, dep] of Object.entries(dependencies)) {
        resolvedDeps[name] = await dep.resolve(overrides);
      }
      const result = await handler(args, resolvedDeps);
      return serializeToolResult(result);
    },
  };
}
