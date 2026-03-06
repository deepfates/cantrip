import type { GateDefinition } from "../../llm/base";

/** Extract parameter names from a gate definition's JSON schema properties. */
export function getParameterNames(definition: GateDefinition): string[] {
  const props = definition.parameters?.properties;
  if (!props || typeof props !== "object") return [];
  return Object.keys(props as Record<string, unknown>);
}

/** Produce a rich one-line description of a state entry for capabilityDocs(). */
export function describeStateEntry(val: unknown): string {
  if (typeof val === "string") {
    const preview = val.slice(0, 100).replace(/\n/g, " ");
    return `string(${val.length} chars) — "${preview}${val.length > 100 ? "..." : ""}"`;
  }
  if (Array.isArray(val)) {
    const elemType = val.length > 0 ? typeof val[0] : "empty";
    let preview: string;
    try { preview = JSON.stringify(val.slice(0, 3)); } catch { preview = "[...]"; }
    if (preview.length > 200) preview = preview.slice(0, 200) + "...";
    return `Array(${val.length} items, ${elemType}) — ${preview}`;
  }
  if (typeof val === "object" && val !== null) {
    const keys = Object.keys(val);
    let preview: string;
    try { preview = JSON.stringify(val); } catch { preview = "{...}"; }
    if (preview.length > 200) preview = preview.slice(0, 200) + "...";
    return `Object{${keys.length} keys: ${keys.join(", ")}} — ${preview}`;
  }
  if (typeof val === "number" || typeof val === "boolean") {
    return `${typeof val}(${val})`;
  }
  return typeof val;
}

/** JSON.stringify with handling for bigints, symbols, functions, errors, and cycles. */
export function safeStringify(value: unknown): string | null {
  try {
    return JSON.stringify(
      value,
      (_key, val) => {
        if (typeof val === "bigint") return val.toString();
        if (typeof val === "symbol") return val.toString();
        if (typeof val === "function") {
          return `[Function ${val.name || "anonymous"}]`;
        }
        if (val instanceof Error) {
          return { name: val.name, message: val.message, stack: val.stack };
        }
        return val;
      },
      2,
    );
  } catch {
    return null;
  }
}

/** Format a dumped value to a display string. */
export function formatDumpedValue(value: unknown): string {
  if (typeof value === "string") return value;
  if (value === undefined) return "undefined";
  if (value === null) return "null";
  const json = safeStringify(value);
  return json ?? String(value);
}

/** Combine execution output with console logs into a single string. */
export function formatOutput(value: unknown, logs: string[] | null): string {
  const logText = logs && logs.length ? logs.join("\n") : "";
  const valueText =
    value === undefined
      ? "undefined"
      : value === null
        ? "null"
        : formatDumpedValue(value);

  if (logText && valueText === "undefined") return logText;
  if (logText) return `${logText}\n${valueText}`;
  return valueText;
}
