import { tool } from "../decorator";
import { z } from "zod";
import {
  BrowserContext,
  getBrowserContext,
  getBrowserContextInteractive,
  getBrowserContextReadonly,
} from "./browser_context";

const DEFAULT_MAX_OUTPUT_CHARS = 9500;

/**
 * Browser automation tool using Taiko.
 *
 * Executes Taiko code in a persistent browser session. All Taiko functions
 * are available: goto, click, write, text, button, link, evaluate, etc.
 *
 * IMPORTANT: Use `return` to get values back. This tool executes code via
 * Function(), so you must explicitly return values you want to retrieve.
 *
 * Meta commands:
 *   .code     - export recorded history as a runnable Taiko script
 *   .reset    - reset the browser session
 *
 * Examples:
 *   return await currentURL()                    - returns the URL
 *   await goto('...'); return await title()      - navigate then return title
 *   return { url: await currentURL(), title: await title() }  - return object
 *
 * Key Taiko patterns:
 *
 * Navigation:
 *   await goto('https://example.com')
 *   await reload()
 *   await goBack()
 *   return await currentURL()
 *   return await title()
 *
 * Selectors (find elements by visible text/labels):
 *   button('Submit')           - <button>Submit</button>
 *   link('Click here')         - <a>Click here</a>
 *   textBox('Email')           - input labeled "Email"
 *   text('Welcome')            - any element with "Welcome"
 *   $('css-selector')          - CSS selector
 *   $('//xpath')               - XPath selector
 *
 * Proximity selectors (combine for precision):
 *   button('Edit', near('John'))
 *   textBox('Password', below('Username'))
 *   link('Delete', toRightOf('Settings'))
 *
 * Interactions:
 *   await click(button('Submit'))
 *   await write('hello', into(textBox('Search')))
 *   await press('Enter')
 *   await hover(link('Menu'))
 *   await focus(textBox('Name'))
 *   await clear(textBox('Search'))
 *
 * Reading content:
 *   return await text('Welcome').exists()      - check if text exists
 *   return await text('Welcome').text()        - get the text
 *   return await $('h1').text()                - get element text
 *   return await textBox('Email').value()      - get input value
 *   return await evaluate(() => document.body.innerText)  - run JS in browser
 *
 * Waiting:
 *   await waitFor(1000)                 - wait ms
 *   await waitFor('Loading...')         - wait for text to appear
 *   await waitFor(() => condition)      - wait for condition
 */

type BrowserToolOptions = {
  code: string;
  timeout_ms?: number;
  max_output_chars?: number;
  reset_session?: boolean;
};

const browserSchema = z.object({
  code: z
    .string()
    .describe(
      "Taiko code to execute. Use .code to export history or .reset to reset session.",
    ),
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
  reset_session: z
    .boolean()
    .describe("Reset the browser session before running code.")
    .optional(),
});

function createBrowserTool({
  name,
  description,
  ctxDependency,
}: {
  name: string;
  description: string;
  ctxDependency: typeof getBrowserContext;
}) {
  return tool(
    description,
    async (
      { code, timeout_ms, max_output_chars, reset_session }: BrowserToolOptions,
      deps,
    ) => {
      const ctx = deps.ctx as BrowserContext;
      const maxChars = max_output_chars ?? DEFAULT_MAX_OUTPUT_CHARS;

      const result = await ctx.evalCode(code, {
        timeoutMs: timeout_ms,
        resetSession: reset_session,
      });

      if (!result.ok) {
        return truncateOutput(`Error: ${result.error}`, maxChars);
      }

      return truncateOutput(result.output, maxChars);
    },
    {
      name,
      zodSchema: browserSchema,
      dependencies: { ctx: ctxDependency },
    },
  );
}

export const browser = createBrowserTool({
  name: "browser",
  description:
    "Execute Taiko code in a persistent browser session. Full capabilities. Use goto() to navigate, click/write for interactions, text/button/link for selectors, evaluate() for JS execution. Use `return` to get values back. State persists across calls.",
  ctxDependency: getBrowserContext,
});

export const browser_interactive = createBrowserTool({
  name: "browser_interactive",
  description:
    "Execute Taiko code in a persistent browser session with interaction-only capabilities (no evaluate/intercept/cookies/permissions/CDP). Use `return` to get values back. State persists across calls.",
  ctxDependency: getBrowserContextInteractive,
});

export const browser_readonly = createBrowserTool({
  name: "browser_readonly",
  description:
    "Execute Taiko code in a persistent browser session with read-only capabilities (no interactions, no evaluate/intercept/cookies/permissions/CDP). Use `return` to get values back. State persists across calls.",
  ctxDependency: getBrowserContextReadonly,
});

function truncateOutput(output: string, maxChars: number): string {
  if (output.length <= maxChars) return output;

  const lastNewline = output.lastIndexOf("\n", maxChars);
  const cutoff = lastNewline > maxChars / 2 ? lastNewline : maxChars;
  return (
    output.substring(0, cutoff) +
    `\n\n... [output truncated at ${maxChars} chars]`
  );
}
