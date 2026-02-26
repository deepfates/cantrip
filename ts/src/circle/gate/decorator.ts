import type { JsonSchema } from "../../crystal/crystal";
import type { ContentPartImage, ContentPartText } from "../../crystal/messages";
import { Depends, type DependencyOverrides } from "./depends";

export type GateContent = string | Array<ContentPartText | ContentPartImage>;

export type GateHandler<TArgs extends Record<string, any>, TResult> = (
  args: TArgs,
  deps: Record<string, any>,
) => Promise<TResult> | TResult;

export type GateOptions = {
  name?: string;
  schema?: JsonSchema;
  params?: Record<string, string>;
  zodSchema?: any;
  ephemeral?: number | boolean;
  dependencies?: Record<string, Depends<any>>;
};

export class Gate<TArgs extends Record<string, any> = Record<string, any>> {
  name: string;
  description: string;
  schema: JsonSchema;
  handler: GateHandler<TArgs, any>;
  ephemeral: number | boolean;
  dependencies: Record<string, Depends<any>>;

  constructor(
    description: string,
    handler: GateHandler<TArgs, any>,
    options?: GateOptions,
  ) {
    const name = options?.name || handler.name;
    if (!name) {
      throw new Error(
        "Gate name is required. Either provide a named function or pass { name: 'gate_name' } in options. " +
          "Arrow functions like `async () => ...` have no name - use `async function myGate() {...}` or provide an explicit name.",
      );
    }
    this.name = name;
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
  ): Promise<GateContent> {
    const resolvedDeps: Record<string, any> = {};
    for (const [name, dep] of Object.entries(this.dependencies)) {
      resolvedDeps[name] = await dep.resolve(overrides);
    }
    const result = await this.handler(args, resolvedDeps);
    return serializeBoundGate(result);
  }
}

export function gate<TArgs extends Record<string, any>>(
  description: string,
  handler: GateHandler<TArgs, any>,
  options?: GateOptions,
): Gate<TArgs> {
  return new Gate(description, handler, options);
}

export function serializeBoundGate(result: any): GateContent {
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
  const type = def.type;

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

  if (type === "string") return { type: "string" };
  if (type === "number") return { type: "number" };
  if (type === "boolean") return { type: "boolean" };

  if (type === "array") {
    return { type: "array", items: zodToSchema(def.element) };
  }

  if (type === "optional") {
    return { ...zodToSchema(def.innerType), _optional: true };
  }

  if (type === "object") {
    const shape = def.shape ?? {};
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
