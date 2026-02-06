# 📜 cantrip

A template for building your own agents. Clone it, learn from it, make it yours.

## What is an agent?

An agent is a loop. You give an LLM a set of tools, ask it a question, and it responds by either answering or asking to use a tool. If it asks for a tool, you run that tool and show it the result. Then it either answers, or asks for another tool. This continues until it's done.

```ts
while (true) {
  const response = await llm.invoke(messages, tools);
  messages.push(response);
  if (!response.tool_calls) break;
  for (const call of response.tool_calls) {
    messages.push(await execute(call));
  }
}
```

That's the core of it. The LLM decides what to do, the tools let it act, and the loop keeps going until there's nothing left to do.

## How does it know when to stop?

The loop above stops when the LLM responds without asking for any tools. But sometimes you want the agent to explicitly signal "I'm done, here's the answer." That's what the `done` tool is for:

```ts
const done = tool(
  "Signal that you've finished the task",
  async ({ result }: { result: string }) => {
    throw new TaskComplete(result);
  },
  { name: "done", params: { result: "string" } }
);
```

When the LLM calls `done`, the tool throws `TaskComplete`, which breaks out of the loop and returns the result. This gives you clean completion semantics instead of trying to guess when the model is finished.

## What are tools?

Tools are functions the agent can call. Each tool has a name, a description (so the LLM knows when to use it), and a schema for its parameters.

```ts
const add = tool(
  "Add two numbers together",
  async ({ a, b }: { a: number; b: number }) => a + b,
  { name: "add", params: { a: "number", b: "number" } }
);
```

The tools you give an agent define what it can do. An agent with `bash`, `read`, and `write` tools can interact with your filesystem. An agent with a `browser` tool can surf the web. An agent with just `add` and `done` can do arithmetic. The tools are the agent's capabilities.

## Get started

This is a GitHub template. Clone it to start your own project:

```bash
gh repo create my-agent --template deepfates/cantrip
cd my-agent
bun install
bun run examples/02_quick_start.ts
```

## Learn by example

The examples build on each other. Work through them in order.

### The basics

**[`01_core_loop.ts`](examples/01_core_loop.ts)** — The loop with a fake LLM that returns hardcoded responses. No API keys needed. Start here to see how the pieces fit together.

**[`02_quick_start.ts`](examples/02_quick_start.ts)** — A real agent using Claude. Has an `add` tool and a `done` tool. Your first working agent.

**[`03_providers.ts`](examples/03_providers.ts)** — Shows how to swap between Anthropic, OpenAI, Google, OpenRouter, and local models.

**[`04_dependency_injection.ts`](examples/04_dependency_injection.ts)** — How to give tools access to databases, API clients, or test mocks.

### Builtin tool modules

**[`05_fs_agent.ts`](examples/05_fs_agent.ts)** — A coding agent with sandboxed filesystem tools (`read`, `write`, `edit`, `glob`, `bash`).

**[`06_js_agent.ts`](examples/06_js_agent.ts)** — A computational agent with two JavaScript tools: `js` (persistent REPL, no I/O) and `js_run` (fresh sandbox with fetch and virtual fs).

**[`07_browser_agent.ts`](examples/07_browser_agent.ts)** — A web browsing agent with a persistent headless browser (via Taiko).

### Putting it together

**[`08_full_agent.ts`](examples/08_full_agent.ts)** — Combines filesystem, JavaScript, and browser tools into one agent. Use this as a starting point for your own agent.

### Advanced patterns

**[`09_rlm.ts`](examples/09_rlm.ts)** — Recursive Language Model. Handle massive contexts (10M+ tokens) by keeping data in a sandbox instead of the prompt. The LLM writes code to explore it and can spawn sub-agents to analyze chunks.

**[`10_rlm.ts`](examples/10_rlm.ts)** — Interactive RLM REPL. Load a file as context and query it conversationally.

## Included Tools Library

While you can write your own tools, Cantrip comes with a few "batteries-included" modules:

**FileSystem (`src/tools/builtin/fs`)** — Lightly sandboxed access to the filesystem. Includes `read` (with pagination), `write` (with size limits), `edit`, `glob`, and `bash`.

**Browser (`src/tools/builtin/browser`)** — Headless browser automation built on Taiko. Persists session state across tool calls.

**JavaScript Sandbox (`src/tools/builtin/js`)** — Secure WASM-based JavaScript runtime (QuickJS). Perfect for agents that need to perform calculations or data processing without risking the host machine.

**RLM (`src/rlm`)** — Recursive Language Model pattern. Offload massive contexts to a JavaScript sandbox and let the LLM explore them programmatically. Supports recursive sub-agents for divide-and-conquer on huge datasets. Based on [Zhang et al. 2026](https://arxiv.org/abs/2512.24601).

## Optional features

The `Agent` class includes some features you can turn on or off:

**Retries** — Automatically retry when the LLM returns rate limit errors or transient failures. On by default.

**Ephemerals** — Some tools produce large outputs (like screenshots) that eat up context. Mark a tool as `ephemeral: 3` to keep only its last 3 results in the conversation history.

**Compaction** — When the conversation gets too long, summarize it to free up context space. Configure with `compaction: { threshold_ratio: 0.8 }`.

If you don't need these, use `CoreAgent` instead, or disable them in `Agent`.

## Providers

```ts
import {
  ChatAnthropic,
  ChatOpenAI,
  ChatGoogle,
  ChatLMStudio,
  ChatOpenRouter,
} from "cantrip/llm";
```

- **ChatLMStudio** — points at the LM Studio local OpenAI-compatible server (`http://localhost:1234/v1` by default) and doesn’t require an API key unless you provide one via `LM_STUDIO_API_KEY`.
- **ChatOpenRouter** — speaks to `https://openrouter.ai/api/v1`, automatically adding the attribution headers OpenRouter expects (`HTTP-Referer`, `X-Title`) from env vars (`OPENROUTER_HTTP_REFERER`, `OPENROUTER_TITLE`). Set `OPENROUTER_API_KEY` or pass `api_key`; you can disable the attribution headers with `attribution_headers: false` if you manage them yourself.
- **ChatOpenAI** (and friends) merge any custom `headers` you pass; `require_api_key` controls whether missing keys throw (default `true`). Passing `api_key: null` still falls back to the relevant env var for compatibility.

## The philosophy

Most agent frameworks add layers between you and the model: planning systems, verification steps, output parsers, state machines. The idea behind cantrip is that you probably don't need most of that. LLMs already know how to reason and use tools. Your job is to give them good tools and get out of the way.

Start simple. Add complexity when you feel the pain, not before. If you want the full argument, read [The Bitter Lesson of Agent Frameworks](https://browser-use.com/posts/bitter-lesson-agent-frameworks).

## Make it yours

Read the source. It's not much code. Change whatever doesn't fit your use case. Delete what you don't need. This is a starting point, not a dependency.

## License

MIT
