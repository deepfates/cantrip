export type SchemaOptimizerOptions = {
  removeMinItems?: boolean;
  removeDefaults?: boolean;
};

export class SchemaOptimizer {
  static createOptimizedJsonSchema(
    schema: Record<string, any>,
    options: SchemaOptimizerOptions = {},
  ): Record<string, any> {
    const cloned = JSON.parse(JSON.stringify(schema));
    const defs = cloned.$defs ?? {};
    delete cloned.$defs;

    const resolved = resolveRefs(cloned, defs);
    ensureAdditionalPropertiesFalse(resolved);
    if (options.removeMinItems || options.removeDefaults) {
      removeForbiddenFields(resolved, options);
    }
    return resolved;
  }
}

function resolveRefs(obj: any, defs: Record<string, any>): any {
  if (Array.isArray(obj)) return obj.map((item) => resolveRefs(item, defs));
  if (!obj || typeof obj !== "object") return obj;

  if (obj.$ref && typeof obj.$ref === "string") {
    const refName = obj.$ref.split("/").pop() ?? "";
    const resolved = defs[refName] ? resolveRefs(defs[refName], defs) : {};
    const merged = { ...resolved, ...obj };
    delete merged.$ref;
    return merged;
  }

  const out: any = {};
  for (const [key, value] of Object.entries(obj)) {
    out[key] = resolveRefs(value, defs);
  }
  return out;
}

function ensureAdditionalPropertiesFalse(obj: any): void {
  if (Array.isArray(obj)) {
    obj.forEach(ensureAdditionalPropertiesFalse);
    return;
  }
  if (!obj || typeof obj !== "object") return;

  if (obj.type === "object") {
    obj.additionalProperties = false;
  }

  for (const value of Object.values(obj)) {
    if (typeof value === "object") ensureAdditionalPropertiesFalse(value);
  }
}

function removeForbiddenFields(
  obj: any,
  options: SchemaOptimizerOptions,
): void {
  if (Array.isArray(obj)) {
    obj.forEach((item) => removeForbiddenFields(item, options));
    return;
  }
  if (!obj || typeof obj !== "object") return;

  if (options.removeMinItems) {
    delete obj.minItems;
    delete obj.min_items;
  }
  if (options.removeDefaults) {
    delete obj.default;
  }

  for (const value of Object.values(obj)) {
    if (typeof value === "object") removeForbiddenFields(value, options);
  }
}
