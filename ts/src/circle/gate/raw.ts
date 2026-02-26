import type { GateDefinition } from "../../crystal/crystal";
import type { DependencyOverrides } from "./depends";
import { Depends } from "./depends";
import { serializeBoundGate, type GateContent } from "./decorator";
import type { BoundGate } from "./gate";

export type RawGateHandler<TArgs extends Record<string, any>, TResult> = (
  args: TArgs,
  deps: Record<string, any>,
) => Promise<TResult> | TResult;

export type RawGateOptions = {
  ephemeral?: number | boolean;
  dependencies?: Record<string, Depends<any>>;
};

export type RawGateDefinition = {
  name: string;
  description: string;
  parameters: GateDefinition["parameters"];
  strict?: boolean;
};

export function rawGate<TArgs extends Record<string, any>>(
  definition: RawGateDefinition,
  handler: RawGateHandler<TArgs, any>,
  options?: RawGateOptions,
): BoundGate {
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
    async execute(args: TArgs, overrides?: DependencyOverrides): Promise<GateContent> {
      const resolvedDeps: Record<string, any> = {};
      for (const [name, dep] of Object.entries(dependencies)) {
        resolvedDeps[name] = await dep.resolve(overrides);
      }
      const result = await handler(args, resolvedDeps);
      return serializeBoundGate(result);
    },
  };
}
