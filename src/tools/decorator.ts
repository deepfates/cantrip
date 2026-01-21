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
  params?: Record<string, string>;
  zodSchema?: any;
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
      (options?.zodSchema
        ? schemaFromZod(options.zodSchema)
        : options?.params
          ? schemaFromParams(options.params)
          : ({
              type: "object",
              properties: {},
              required: [],
              additionalProperties: false,
            } as JsonSchema));
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

function schemaFromParams(params: Record<string, string>): JsonSchema {
  const properties: Record<string, any> = {};
  const required: string[] = [];

  for (const [key, rawType] of Object.entries(params)) {
    const { schema, optional } = parseParamType(rawType);
    properties[key] = schema;
    if (!optional) required.push(key);
  }

  return {
    type: "object",
    properties,
    required,
    additionalProperties: false,
  };
}

function parseParamType(raw: string): {
  schema: Record<string, any>;
  optional: boolean;
} {
  let type = raw.trim();
  let optional = false;
  if (type.endsWith("?")) {
    optional = true;
    type = type.slice(0, -1);
  }

  if (type.endsWith("[]")) {
    const itemType = type.slice(0, -2);
    return {
      schema: { type: "array", items: parseParamType(itemType).schema },
      optional,
    };
  }

  if (type.startsWith("enum:")) {
    const values = type.slice("enum:".length).split("|");
    return { schema: { type: "string", enum: values }, optional };
  }

  if (type === "string") return { schema: { type: "string" }, optional };
  if (type === "number") return { schema: { type: "number" }, optional };
  if (type === "integer") return { schema: { type: "integer" }, optional };
  if (type === "boolean") return { schema: { type: "boolean" }, optional };
  if (type === "object")
    return {
      schema: { type: "object", additionalProperties: false },
      optional,
    };

  return { schema: { type: "string" }, optional };
}

function schemaFromZod(zodSchema: any): JsonSchema {
  const result = zodToSchema(zodSchema);
  if (result.type === "object") {
    result.additionalProperties = false;
  }
  return result;
}

function zodToSchema(zodSchema: any): Record<string, any> {
  const def = zodSchema?._def ?? {};
  const typeName = def.typeName;

  if (typeName === "ZodString") return { type: "string" };
  if (typeName === "ZodNumber") return { type: "number" };
  if (typeName === "ZodBoolean") return { type: "boolean" };

  if (typeName === "ZodArray") {
    return { type: "array", items: zodToSchema(def.type) };
  }

  if (typeName === "ZodOptional") {
    return { ...zodToSchema(def.innerType), _optional: true };
  }

  if (typeName === "ZodObject") {
    const shapeGetter = def.shape;
    const shape =
      typeof shapeGetter === "function" ? shapeGetter() : (def.shape ?? {});
    const properties: Record<string, any> = {};
    const required: string[] = [];

    for (const [key, value] of Object.entries(shape)) {
      const schema = zodToSchema(value);
      const optional = schema._optional === true;
      if (optional) delete schema._optional;
      properties[key] = schema;
      if (!optional) required.push(key);
    }

    return {
      type: "object",
      properties,
      required,
      additionalProperties: false,
    };
  }

  return { type: "string" };
}
