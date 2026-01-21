import { describe, expect, test } from "bun:test";

import { ChatAzureOpenAI } from "../src/llm/azure/chat";

const model = "deployment-name";


describe("azure openai", () => {
  test("builds deployment chat completions URL with api-version", async () => {
    const originalFetch = globalThis.fetch;
    const requests: Array<{ url: string; headers: Record<string, string> }> = [];

    globalThis.fetch = async (url, init) => {
      const headers = (init?.headers ?? {}) as Record<string, string>;
      requests.push({ url: String(url), headers });
      return new Response(
        JSON.stringify({ choices: [{ message: { content: "ok" } }] }),
        { status: 200 }
      );
    };

    const llm = new ChatAzureOpenAI({
      model,
      api_key: "test-key",
      azure_endpoint: "https://example.openai.azure.com",
      azure_deployment: "my-deploy",
      api_version: "2024-10-21",
    } as any);

    await llm.ainvoke([{ role: "user", content: "hi" } as any]);

    expect(requests.length).toBe(1);
    expect(requests[0].url).toBe(
      "https://example.openai.azure.com/openai/deployments/my-deploy/chat/completions?api-version=2024-10-21"
    );
    expect(requests[0].headers["api-key"]).toBe("test-key");

    globalThis.fetch = originalFetch;
  });
});
