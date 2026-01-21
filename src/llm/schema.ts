export class SchemaOptimizer {
  static createOptimizedJsonSchema(schema: Record<string, any>): Record<string, any> {
    const cloned = JSON.parse(JSON.stringify(schema));
    ensureAdditionalPropertiesFalse(cloned);
    return cloned;
  }
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
