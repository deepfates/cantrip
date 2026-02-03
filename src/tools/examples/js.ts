import { tool } from "../decorator";
import { z } from "zod";
import { JsContext, getJsContext } from "./js_context";

// Mimicking the output limits from fs.ts
const DEFAULT_MAX_OUTPUT_CHARS = 9500;

export const js = tool(
  "Execute JavaScript in a persistent, isolated sandbox. State persists across calls. No host adapters (fetch/fs); use tools for I/O.",
  async (
    {
      code,
      timeout_ms,
      max_output_chars,
    }: { code: string; timeout_ms?: number; max_output_chars?: number },
    deps,
  ) => {
    const ctx = deps.ctx as JsContext;
    const maxChars = max_output_chars ?? DEFAULT_MAX_OUTPUT_CHARS;

    try {
      const result = await ctx.evalCode(code, {
        executionTimeoutMs: timeout_ms,
      });

      if (!result.ok) {
        return truncateOutput(`Error: ${result.error}`, maxChars);
      }

      return truncateOutput(result.output, maxChars);
    } catch (e: any) {
      return truncateOutput(`Error: ${String(e?.message ?? e)}`, maxChars);
    }
  },
  {
    name: "js",
    zodSchema: z.object({
      code: z
        .string()
        .describe("The Javascript code to execute in the sandbox."),
      timeout_ms: z
        .number()
        .int()
        .positive()
        .describe("Execution timeout in milliseconds.")
        .optional(),
      max_output_chars: z
        .number()
        .int()
        .positive()
        .describe("Maximum number of output characters.")
        .optional(),
    }),
    dependencies: { ctx: getJsContext },
  },
);

function truncateOutput(output: string, maxChars: number): string {
  if (output.length <= maxChars) return output;

  const lastNewline = output.lastIndexOf("\n", maxChars);
  const cutoff = lastNewline > maxChars / 2 ? lastNewline : maxChars;
  return (
    output.substring(0, cutoff) +
    `\n\n... [output truncated at ${maxChars} chars]`
  );
}
