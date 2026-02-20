export type ProgressEvent =
  | { type: "sub_entity_start"; depth: number; query: string }
  | { type: "sub_entity_end"; depth: number }
  | { type: "batch_start"; depth: number; count: number }
  | {
      type: "batch_item";
      depth: number;
      index: number;
      total: number;
      query: string;
    }
  | { type: "batch_end"; depth: number };

export type ProgressCallback = (event: ProgressEvent) => void;

/** Default progress callback: logs to stderr in the tree format used by the REPL. */
export function defaultProgress(depth: number): ProgressCallback {
  const indent = "  ".repeat(depth);
  return (event) => {
    switch (event.type) {
      case "sub_entity_start": {
        const preview =
          event.query.slice(0, 50) + (event.query.length > 50 ? "..." : "");
        console.error(`${indent}├─ [depth:${event.depth}] "${preview}"`);
        break;
      }
      case "sub_entity_end":
        console.error(`${indent}└─ [depth:${event.depth}] done`);
        break;
      case "batch_start":
        console.error(
          `${indent}├─ [depth:${event.depth}] llm_batch(${event.count} tasks)`,
        );
        break;
      case "batch_item": {
        const preview =
          event.query.slice(0, 30) + (event.query.length > 30 ? "..." : "");
        console.error(
          `${indent}│  ├─ [${event.index + 1}/${event.total}] "${preview}"`,
        );
        break;
      }
      case "batch_end":
        console.error(`${indent}└─ [depth:${event.depth}] batch complete`);
        break;
    }
  };
}
