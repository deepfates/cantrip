import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { promises as fs } from "fs";
import path from "path";
import os from "os";
import { pathToFileURL } from "url";
import type { GateContent } from "../src/circle/gate/decorator";

// These will be implemented
import {
  browser,
  browser_interactive,
  browser_readonly,
} from "../src/circle/gate/builtin/browser";
import {
  BrowserContext,
  getBrowserContext,
  getBrowserContextInteractive,
  getBrowserContextReadonly,
} from "../src/circle/gate/builtin/browser_context";

describe("browser tool", () => {
  let ctx: BrowserContext;
  let ctxInteractive: BrowserContext;
  let ctxReadonly: BrowserContext;
  let dependency_overrides: Map<any, () => BrowserContext>;
  let dependency_overrides_interactive: Map<any, () => BrowserContext>;
  let dependency_overrides_readonly: Map<any, () => BrowserContext>;

  const exampleHtml = `
    <!doctype html>
    <html>
      <head>
        <title>Example Domain</title>
      </head>
      <body>
        <h1>Example Domain</h1>
        <p>Example content</p>
        <a href="https://example.com">More information</a>
      </body>
    </html>
  `;
  let exampleUrl = "";
  let tempDir = "";

  function expectString(result: GateContent): asserts result is string {
    if (typeof result !== "string") {
      throw new Error("Expected string tool output");
    }
  }

  beforeAll(async () => {
    tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "cantrip-browser-"));
    const filePath = path.join(tempDir, "example.html");
    await fs.writeFile(filePath, exampleHtml, "utf8");
    exampleUrl = pathToFileURL(filePath).toString();

    ctx = await BrowserContext.create({ headless: true, profile: "full" });
    ctxInteractive = await BrowserContext.create({
      headless: true,
      profile: "interactive",
    });
    ctxReadonly = await BrowserContext.create({
      headless: true,
      profile: "readonly",
    });
    dependency_overrides = new Map([[getBrowserContext, () => ctx]]);
    dependency_overrides_interactive = new Map([
      [getBrowserContextInteractive, () => ctxInteractive],
    ]);
    dependency_overrides_readonly = new Map([
      [getBrowserContextReadonly, () => ctxReadonly],
    ]);
  });

  afterAll(async () => {
    await ctx?.dispose();
    await ctxInteractive?.dispose();
    await ctxReadonly?.dispose();
    if (tempDir) {
      await fs.rm(tempDir, { recursive: true, force: true });
    }
  });

  describe("navigation", () => {
    test("navigates to a URL with goto", async () => {
      const result = await browser.execute(
        {
          code: `await goto('${exampleUrl}'); return await currentURL()`,
        },
        dependency_overrides,
      );
      expectString(result);
      expect(result).toContain("file:");
    }, 15000);

    test("gets page title", async () => {
      const result = await browser.execute(
        { code: `await goto('${exampleUrl}'); return await title()` },
        dependency_overrides,
      );
      expectString(result);
      expect(result.toLowerCase()).toContain("example");
    }, 15000);
  });

  describe("reading page content", () => {
    test("extracts text with evaluate", async () => {
      const result = await browser.execute(
        {
          code: `
            await goto('${exampleUrl}');
            return await evaluate(() => document.body.innerText)
          `,
        },
        dependency_overrides,
      );
      expectString(result);
      expect(result.toLowerCase()).toContain("example");
    }, 15000);

    test("checks if text exists on page", async () => {
      const result = await browser.execute(
        {
          code: `
            await goto('${exampleUrl}');
            return await text('Example Domain').exists()
          `,
        },
        dependency_overrides,
      );
      expectString(result);
      expect(result).toBe("true");
    }, 15000);

    test("extracts element text with text().text()", async () => {
      const result = await browser.execute(
        {
          code: `
            await goto('${exampleUrl}');
            return await $('h1').text()
          `,
        },
        dependency_overrides,
      );
      expectString(result);
      expect(result).toContain("Example Domain");
    }, 15000);
  });

  describe("interactions", () => {
    test("clicks an element", async () => {
      // Test clicking using a button we create via evaluate
      const result = await browser.execute(
        {
          code: `
            await goto('${exampleUrl}');
            await evaluate(() => {
              window.clickCount = 0;
              const btn = document.createElement('button');
              btn.id = 'test-btn';
              btn.textContent = 'Click Me';
              btn.onclick = () => { window.clickCount++; };
              document.body.appendChild(btn);
            });
            await click(button('Click Me'));
            return await evaluate(() => window.clickCount)
          `,
        },
        dependency_overrides,
      );
      expectString(result);
      expect(result).toBe("1");
    }, 20000);

    test("types into a text field", async () => {
      // Test typing using evaluate to create a temporary input
      const result = await browser.execute(
        {
          code: `
            await goto('${exampleUrl}');
            await evaluate(() => {
              const input = document.createElement('input');
              input.id = 'test-input';
              input.type = 'text';
              document.body.appendChild(input);
            });
            await write('hello world', into(textBox({id: 'test-input'})));
            return await textBox({id: 'test-input'}).value()
          `,
        },
        dependency_overrides,
      );
      expectString(result);
      expect(result).toContain("hello world");
    }, 20000);
  });

  describe("state persistence", () => {
    test("maintains browser state between calls", async () => {
      // First call: navigate
      await browser.execute(
        { code: `await goto('${exampleUrl}')` },
        dependency_overrides,
      );

      // Second call: check we're still there
      const result = await browser.execute(
        { code: `return await currentURL()` },
        dependency_overrides,
      );
      expectString(result);
      expect(result).toContain("file:");
    }, 20000);
  });

  describe("error handling", () => {
    test("returns error for invalid code", async () => {
      const result = await browser.execute(
        { code: `function {` },
        dependency_overrides,
      );
      expectString(result);
      expect(result.startsWith("Error:")).toBe(true);
    });

    test("returns error when element not found", async () => {
      const result = await browser.execute(
        {
          code: `
            await goto('${exampleUrl}');
            await click(button('NonexistentButton12345'))
          `,
        },
        dependency_overrides,
      );
      expectString(result);
      expect(result.startsWith("Error:")).toBe(true);
    }, 15000);
  });

  describe("output handling", () => {
    test("returns stringified objects", async () => {
      const result = await browser.execute(
        {
          code: `
            await goto('${exampleUrl}');
            return { url: await currentURL(), title: await title() }
          `,
        },
        dependency_overrides,
      );
      expectString(result);
      const parsed = JSON.parse(result);
      expect(parsed.url).toContain("file:");
      expect(parsed.title).toBeTruthy();
    }, 15000);

    test("returns arrays properly", async () => {
      const result = await browser.execute(
        {
          code: `
            await goto('${exampleUrl}');
            const links = await $('a').elements();
            return await Promise.all(links.map(l => l.text()))
          `,
        },
        dependency_overrides,
      );
      expectString(result);
      const parsed = JSON.parse(result);
      expect(Array.isArray(parsed)).toBe(true);
    }, 15000);

    test("truncates large output", async () => {
      const result = await browser.execute(
        {
          code: `return 'a'.repeat(200)`,
          max_output_chars: 100,
        },
        dependency_overrides,
      );
      expectString(result);
      expect(result).toContain("... [output truncated at 100 chars]");
    });
  });

  describe("timeout handling", () => {
    test("respects timeout_ms option", async () => {
      const result = await browser.execute(
        {
          code: `
            await goto('${exampleUrl}');
            await waitFor(5000);
            return 'done'
          `,
          timeout_ms: 1000,
        },
        dependency_overrides,
      );
      expectString(result);
      expect(result.startsWith("Error:")).toBe(true);
    }, 10000);
  });

  describe("history export", () => {
    test("exports a .code script", async () => {
      await browser.execute(
        { code: `await goto('${exampleUrl}')` },
        dependency_overrides,
      );
      const result = await browser.execute(
        { code: `.code` },
        dependency_overrides,
      );
      expectString(result);
      expect(result).toContain("openBrowser");
      expect(result).toContain("goto");
    });
  });

  describe("meta commands", () => {
    test("reset command resets session", async () => {
      const result = await browser.execute(
        { code: `.reset` },
        dependency_overrides,
      );
      expectString(result);
      expect(result).toContain("Session reset.");
    });
  });

  describe("profile enforcement", () => {
    test("interactive blocks evaluate", async () => {
      const result = await browser_interactive.execute(
        {
          code: `
            await goto('${exampleUrl}');
            return await evaluate(() => document.title)
          `,
        },
        dependency_overrides_interactive,
      );
      expectString(result);
      expect(result.startsWith("Error:")).toBe(true);
    }, 15000);

    test("readonly blocks click", async () => {
      const result = await browser_readonly.execute(
        {
          code: `
            await goto('${exampleUrl}');
            await click(link('More information'))
          `,
        },
        dependency_overrides_readonly,
      );
      expectString(result);
      expect(result.startsWith("Error:")).toBe(true);
    }, 15000);
  });
});

describe("BrowserContext", () => {
  test("creates and disposes cleanly", async () => {
    const ctx = await BrowserContext.create({
      headless: true,
      profile: "full",
    });
    expect(ctx).toBeDefined();
    await ctx.dispose();
  }, 30000);

  test("evalCode returns successful result", async () => {
    const ctx = await BrowserContext.create({
      headless: true,
      profile: "full",
    });
    try {
      const tempDir = await fs.mkdtemp(
        path.join(os.tmpdir(), "cantrip-browser-"),
      );
      const filePath = path.join(tempDir, "example.html");
      await fs.writeFile(filePath, "<html><body>Hello</body></html>", "utf8");
      const fileUrl = pathToFileURL(filePath).toString();

      const result = await ctx.evalCode(`
        await goto('${fileUrl}');
        return await currentURL()
      `);
      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.output).toContain("file:");
      }
      await fs.rm(tempDir, { recursive: true, force: true });
    } finally {
      await ctx.dispose();
    }
  }, 30000);

  test("evalCode returns error for failed code", async () => {
    const ctx = await BrowserContext.create({
      headless: true,
      profile: "full",
    });
    try {
      const result = await ctx.evalCode(`throw new Error('test error')`);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.error).toContain("test error");
      }
    } finally {
      await ctx.dispose();
    }
  }, 30000);

  test("reports disposed state", async () => {
    const ctx = await BrowserContext.create({
      headless: true,
      profile: "full",
    });
    await ctx.dispose();
    const result = await ctx.evalCode(`return 1 + 1`);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.toLowerCase()).toContain("disposed");
    }
  }, 30000);

  test("blocks disallowed domains", async () => {
    const ctx = await BrowserContext.create({
      headless: true,
      profile: "full",
      domainPolicy: { deny: ["example.com"] },
    });
    try {
      const result = await ctx.evalCode(`await goto('https://example.com')`);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.error).toContain("Blocked by domain denylist");
      }
    } finally {
      await ctx.dispose();
    }
  }, 30000);
});
