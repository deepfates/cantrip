import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { promises as fs } from "fs";
import path from "path";
import os from "os";
import { pathToFileURL } from "url";

import {
  BrowserContext,
  getBrowserContext,
  getBrowserContextInteractive,
  getBrowserContextReadonly,
} from "../../src/circle/medium/browser/context";

describe("BrowserContext", () => {
  let ctx: BrowserContext;
  let ctxInteractive: BrowserContext;
  let ctxReadonly: BrowserContext;

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
      const result = await ctx.evalCode(
        `await goto('${exampleUrl}'); return await currentURL()`,
      );
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.output).toContain("file:");
    }, 15000);

    test("gets page title", async () => {
      const result = await ctx.evalCode(
        `await goto('${exampleUrl}'); return await title()`,
      );
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.output.toLowerCase()).toContain("example");
    }, 15000);
  });

  describe("reading page content", () => {
    test("extracts text with evaluate", async () => {
      const result = await ctx.evalCode(`
        await goto('${exampleUrl}');
        return await evaluate(() => document.body.innerText)
      `);
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.output.toLowerCase()).toContain("example");
    }, 15000);

    test("checks if text exists on page", async () => {
      const result = await ctx.evalCode(`
        await goto('${exampleUrl}');
        return await text('Example Domain').exists()
      `);
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.output).toBe("true");
    }, 15000);

    test("extracts element text with $(selector).text()", async () => {
      const result = await ctx.evalCode(`
        await goto('${exampleUrl}');
        return await $('h1').text()
      `);
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.output).toContain("Example Domain");
    }, 15000);
  });

  describe("interactions", () => {
    test("clicks an element", async () => {
      const result = await ctx.evalCode(`
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
      `);
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.output).toBe("1");
    }, 20000);

    test("types into a text field", async () => {
      const result = await ctx.evalCode(`
        await goto('${exampleUrl}');
        await evaluate(() => {
          const input = document.createElement('input');
          input.id = 'test-input';
          input.type = 'text';
          document.body.appendChild(input);
        });
        await write('hello world', into(textBox({id: 'test-input'})));
        return await textBox({id: 'test-input'}).value()
      `);
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.output).toContain("hello world");
    }, 20000);
  });

  describe("state persistence", () => {
    test("maintains browser state between calls", async () => {
      await ctx.evalCode(`await goto('${exampleUrl}')`);
      const result = await ctx.evalCode(`return await currentURL()`);
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.output).toContain("file:");
    }, 20000);
  });

  describe("error handling", () => {
    test("returns error for invalid code", async () => {
      const result = await ctx.evalCode(`function {`);
      expect(result.ok).toBe(false);
    });

    test("returns error when element not found", async () => {
      const result = await ctx.evalCode(`
        await goto('${exampleUrl}');
        await click(button('NonexistentButton12345'))
      `);
      expect(result.ok).toBe(false);
    }, 15000);
  });

  describe("output handling", () => {
    test("returns stringified objects", async () => {
      const result = await ctx.evalCode(`
        await goto('${exampleUrl}');
        return { url: await currentURL(), title: await title() }
      `);
      expect(result.ok).toBe(true);
      if (result.ok) {
        const parsed = JSON.parse(result.output);
        expect(parsed.url).toContain("file:");
        expect(parsed.title).toBeTruthy();
      }
    }, 15000);

    test("returns arrays properly", async () => {
      const result = await ctx.evalCode(`
        await goto('${exampleUrl}');
        const links = await $('a').elements();
        return await Promise.all(links.map(l => l.text()))
      `);
      expect(result.ok).toBe(true);
      if (result.ok) {
        const parsed = JSON.parse(result.output);
        expect(Array.isArray(parsed)).toBe(true);
      }
    }, 15000);
  });

  describe("timeout handling", () => {
    test("respects timeoutMs option", async () => {
      const result = await ctx.evalCode(
        `await goto('${exampleUrl}'); await waitFor(5000); return 'done'`,
        { timeoutMs: 1000 },
      );
      expect(result.ok).toBe(false);
    }, 10000);
  });

  describe("history export", () => {
    test("exports a .code script", async () => {
      await ctx.evalCode(`await goto('${exampleUrl}')`);
      const result = await ctx.evalCode(`.code`);
      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.output).toContain("openBrowser");
        expect(result.output).toContain("goto");
      }
    });
  });

  describe("meta commands", () => {
    test("reset command resets session", async () => {
      const result = await ctx.evalCode(`.reset`);
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.output).toContain("Session reset.");
    });
  });

  describe("profile enforcement", () => {
    test("interactive blocks evaluate", async () => {
      const result = await ctxInteractive.evalCode(`
        await goto('${exampleUrl}');
        return await evaluate(() => document.title)
      `);
      expect(result.ok).toBe(false);
    }, 15000);

    test("readonly blocks click", async () => {
      const result = await ctxReadonly.evalCode(`
        await goto('${exampleUrl}');
        await click(link('More information'))
      `);
      expect(result.ok).toBe(false);
    }, 15000);
  });

  test("creates and disposes cleanly", async () => {
    const c = await BrowserContext.create({
      headless: true,
      profile: "full",
    });
    expect(c).toBeDefined();
    await c.dispose();
  }, 30000);

  test("reports disposed state", async () => {
    const c = await BrowserContext.create({
      headless: true,
      profile: "full",
    });
    await c.dispose();
    const result = await c.evalCode(`return 1 + 1`);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.toLowerCase()).toContain("disposed");
    }
  }, 30000);

  test("blocks disallowed domains", async () => {
    const c = await BrowserContext.create({
      headless: true,
      profile: "full",
      domainPolicy: { deny: ["example.com"] },
    });
    try {
      const result = await c.evalCode(`await goto('https://example.com')`);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.error).toContain("Blocked by domain denylist");
      }
    } finally {
      await c.dispose();
    }
  }, 30000);
});
