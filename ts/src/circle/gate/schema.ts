import type { JsonSchema } from "../../crystal/crystal";

export type GateSchemaFieldOptions = {
  optional?: boolean;
  description?: string;
};

export class GateSchemaBuilder {
  private properties: Record<string, JsonSchema> = {};
  private required: Set<string> = new Set();

  addString(name: string, options?: GateSchemaFieldOptions): this {
    return this.addField(name, { type: "string" }, options);
  }

  addNumber(name: string, options?: GateSchemaFieldOptions): this {
    return this.addField(name, { type: "number" }, options);
  }

  addInteger(name: string, options?: GateSchemaFieldOptions): this {
    return this.addField(name, { type: "integer" }, options);
  }

  addBoolean(name: string, options?: GateSchemaFieldOptions): this {
    return this.addField(name, { type: "boolean" }, options);
  }

  addEnum(
    name: string,
    values: string[],
    options?: GateSchemaFieldOptions,
  ): this {
    return this.addField(name, { type: "string", enum: values }, options);
  }

  addArray(
    name: string,
    items: JsonSchema,
    options?: GateSchemaFieldOptions,
  ): this {
    return this.addField(name, { type: "array", items }, options);
  }

  addObject(
    name: string,
    schema: JsonSchema,
    options?: GateSchemaFieldOptions,
  ): this {
    return this.addField(name, schema, options);
  }

  addSchema(
    name: string,
    schema: JsonSchema,
    options?: GateSchemaFieldOptions,
  ): this {
    return this.addField(name, schema, options);
  }

  build(): JsonSchema {
    return {
      type: "object",
      properties: this.properties,
      required: Array.from(this.required),
      additionalProperties: false,
    };
  }

  private addField(
    name: string,
    schema: JsonSchema,
    options?: GateSchemaFieldOptions,
  ): this {
    const fieldSchema: JsonSchema = {
      ...schema,
      ...(options?.description ? { description: options.description } : {}),
    };
    this.properties[name] = fieldSchema;
    if (!options?.optional) {
      this.required.add(name);
    }
    return this;
  }
}

export class GateSchema {
  static create(): GateSchemaBuilder {
    return new GateSchemaBuilder();
  }
}
