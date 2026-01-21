import type { JsonSchema } from "../llm/base";
import type { ContentPartImage, ContentPartText } from "../llm/messages";
import { Depends, type DependencyOverrides } from "./depends";

export type ToolContent = string | Array<ContentPartText | ContentPartImage>;

export type ToolHandler<TArgs extends Record<string, any>, TResult> = (
  args: TArgs,
  deps: Record<string, any>,
) => Promise<TResult> | TResult;

export type ToolOptions = {
  name?: string;
  schema?: JsonSchema;
  ephemeral?: number | boolean;
  dependencies?: Record<string, Depends<any>>;
};

export class Tool<TArgs extends Record<string, any> = Record<string, any>> {
  name: string;
  description: string;
  schema: JsonSchema;
  handler: ToolHandler<TArgs, any>;
  ephemeral: number | boolean;
  dependencies: Record<string, Depends<any>>;

  constructor(
    description: string,
    handler: ToolHandler<TArgs, any>,
    options?: ToolOptions,
  ) {
    this.name = options?.name ?? handler.name ?? "tool";
    this.description = description;
    this.schema =
      options?.schema ??
      ({
        type: "object",
        properties: {},
        required: [],
        additionalProperties: false,
      } as JsonSchema);
    this.handler = handler;
    this.ephemeral = options?.ephemeral ?? false;
    this.dependencies = options?.dependencies ?? {};
  }

  get definition() {
    return {
      name: this.name,
      description: this.description,
      parameters: this.schema,
      strict: true,
    };
  }

  async execute(
    args: TArgs,
    overrides?: DependencyOverrides,
  ): Promise<ToolContent> {
    const resolvedDeps: Record<string, any> = {};
    for (const [name, dep] of Object.entries(this.dependencies)) {
      resolvedDeps[name] = await dep.resolve(overrides);
    }

    const result = await this.handler(args, resolvedDeps);
    return serializeToolResult(result);
  }
}

export function tool<TArgs extends Record<string, any>>(
  description: string,
  handler: ToolHandler<TArgs, any>,
  options?: ToolOptions,
): Tool<TArgs> {
  return new Tool(description, handler, options);
}

export function serializeToolResult(result: any): ToolContent {
  if (result === null || result === undefined) return "";
  if (typeof result === "string") return result;

  if (Array.isArray(result) && result.length) {
    const first = result[0];
    if (first?.type === "text" || first?.type === "image_url") {
      return result as Array<ContentPartText | ContentPartImage>;
    }
  }

  if (typeof result === "object") {
    return JSON.stringify(result);
  }

  return String(result);
}
