# simple-agent

A TypeScript agent framework that does almost nothing — and that's the point.

## What This Is

An agent is a while loop. You give an LLM some tools, it calls them, you execute them, repeat until it stops. That's it. That's the whole thing.

```ts
while (true) {
  const response = await llm.invoke(messages, tools);
  if (!response.tool_calls) break;
  for (const call of response.tool_calls) {
    messages.push(await execute(call));
  }
}
```

This library wraps that loop with the minimal scaffolding needed to make it practical: multi-provider LLM support, tool schema validation, context management, and streaming events. Nothing more.

## Why So Minimal?

In 2019, Rich Sutton published [The Bitter Lesson](http://www.incompleteideas.net/IncIdeas/BitterLesson.html), arguing that 70 years of AI research points to one conclusion: general methods that leverage computation beat hand-crafted human knowledge, every time. Chess engines won with brute-force search, not human chess intuition. Speech recognition won with statistical models, not phoneme rules.

The same pattern is playing out with LLM agents. The industry spent 2023-2024 building elaborate frameworks — planners, verifiers, chain-of-thought orchestrators, memory modules, tool routers — only to discover that better models made most of it unnecessary. Meanwhile, the frameworks became liabilities: rigid abstractions that fought against experimentation, layers of indirection that obscured what was actually happening, and dependency graphs that broke in production.

The most successful agents (Claude Code, Cursor, OpenAI's internal tools) converged on the same architecture: a simple loop with tools. No planning modules. No verification layers. Just the model, doing its thing.

This library is a TypeScript port of [browser-use/agent-sdk](https://github.com/browser-use/agent-sdk), which powers browser automation agents that need to be reliable, fast, and easy to modify. The philosophy: give the model maximum freedom, then restrict based on what actually fails in practice.

## Installation

```bash
bun add simple-agent
```

## Quick Start

```ts
import { Agent, TaskComplete, tool } from "simple-agent";
import { ChatAnthropic } from "simple-agent/llm";
import { z } from "zod";

// Define tools with Zod schemas
const add = tool(
  "Add two numbers",
  async ({ a, b }: { a: number; b: number }) => a + b,
  { name: "add", zodSchema: z.object({ a: z.number(), b: z.number() }) }
);

const done = tool(
  "Signal task completion",
  async ({ result }: { result: string }) => {
    throw new TaskComplete(result);
  },
  { name: "done", zodSchema: z.object({ result: z.string() }) }
);

// Create agent and run
const agent = new Agent({
  llm: new ChatAnthropic({ model: "claude-sonnet-4-20250514" }),
  tools: [add, done],
});

const answer = await agent.query("What is 2 + 3?");
console.log(answer); // "5"
```

## The Core Loop

Here's what actually happens when you call `agent.query()`:

1. Your message gets added to the conversation history
2. The LLM is called with the history and available tools
3. If the LLM returns tool calls, each one is executed and results added to history
4. Repeat until the LLM responds without tool calls (or hits max iterations)

That's the entire architecture. Everything else is details.

## Features

### Explicit Completion with Done Tool

By default, the agent stops when the model responds without calling any tools. This works fine for simple tasks, but for complex workflows you often want explicit completion — the model must call a `done` tool to signal it's finished.

```ts
const agent = new Agent({
  llm,
  tools: [...yourTools, doneToolFromAbove],
  require_done_tool: true, // Won't stop until done() is called
});
```

The `TaskComplete` exception is a control flow mechanism: throw it from any tool to immediately end the loop and return the message.

### Context Management

Long-running agents accumulate context. A browser automation agent might generate megabytes of DOM snapshots and screenshots. Without management, you'll hit token limits or degrade model performance (context "rot" typically starts around 25% of the window).

**Ephemeral messages** solve this for repetitive tool outputs. Mark a tool as ephemeral, and only the last N results are kept:

```ts
const screenshot = tool(
  "Take screenshot",
  async () => takeScreenshotBase64(),
  { name: "screenshot", ephemeral: 3 } // Keep only last 3 screenshots in context
);
```

**Compaction** handles the rest. When context exceeds a threshold (default 80% of model's window), the agent summarizes the conversation and continues with the summary:

```ts
const agent = new Agent({
  llm,
  tools,
  compaction: { threshold_ratio: 0.8 },
});
```

### Providers

Built-in adapters for major providers, all implementing the same interface:

```ts
import {
  ChatAnthropic,
  ChatOpenAI,
  ChatGoogle,
  ChatAzureOpenAI,
  ChatGroq,
  ChatMistral,
  ChatOllama,
  ChatDeepSeek,
  ChatCerebras,
} from "simple-agent/llm";

// All work identically
new Agent({ llm: new ChatAnthropic({ model: "claude-sonnet-4-20250514" }), tools });
new Agent({ llm: new ChatOpenAI({ model: "gpt-4o" }), tools });
new Agent({ llm: new ChatGoogle({ model: "gemini-2.0-flash" }), tools });
```

Groq, Mistral, Ollama, DeepSeek, and Cerebras use OpenAI-compatible endpoints under the hood.

### Tool Schemas

Three ways to define tool input schemas, from recommended to quick-and-dirty:

**Zod (recommended)** — full validation, good TypeScript inference:

```ts
import { z } from "zod";

const search = tool(
  "Search the codebase",
  async ({ query, limit }) => searchFiles(query, limit),
  {
    name: "search",
    zodSchema: z.object({
      query: z.string(),
      limit: z.number().optional(),
    }),
  }
);
```

**Fluent builder** — no Zod dependency:

```ts
import { ToolSchema } from "simple-agent";

const schema = ToolSchema.create()
  .addString("query")
  .addInteger("limit", { optional: true })
  .build();

const search = tool("Search the codebase", handler, { name: "search", schema });
```

**Params shorthand** — quick prototyping:

```ts
const search = tool("Search the codebase", handler, {
  name: "search",
  params: { query: "string", limit: "integer?" },
});
```

### Dependency Injection

Tools often need shared resources (database connections, API clients). Rather than globals or closures, use dependency injection:

```ts
import { Depends, tool } from "simple-agent";

function getDatabase() {
  return new Database(process.env.DATABASE_URL);
}

const query = tool(
  "Query database",
  async ({ sql }, deps) => deps.db.execute(sql),
  {
    name: "query",
    params: { sql: "string" },
    dependencies: { db: new Depends(getDatabase) },
  }
);
```

Dependencies are resolved at execution time. Override them for testing:

```ts
const result = await query.execute(
  { sql: "SELECT 1" },
  { db: () => mockDatabase }
);
```

### Streaming

For UIs and logging, stream events as they happen:

```ts
import {
  ToolCallEvent,
  ToolResultEvent,
  FinalResponseEvent,
} from "simple-agent/agent";

for await (const event of agent.query_stream("Do something complex")) {
  if (event instanceof ToolCallEvent) {
    console.log(`Calling: ${event.tool}(${JSON.stringify(event.args)})`);
  } else if (event instanceof ToolResultEvent) {
    console.log(`Result: ${event.result.slice(0, 100)}...`);
  } else if (event instanceof FinalResponseEvent) {
    console.log(`Done: ${event.content}`);
  }
}
```

Event types: `TextEvent`, `ThinkingEvent`, `ToolCallEvent`, `ToolResultEvent`, `StepStartEvent`, `StepCompleteEvent`, `FinalResponseEvent`.

### Observability

Plug in your own tracing/logging:

```ts
import { observe, setObserver } from "simple-agent";

setObserver({
  onStart: (e) => console.log(`[${e.name}] started`),
  onEnd: (e) => console.log(`[${e.name}] completed in ${e.duration_ms}ms`),
  onError: (e) => console.error(`[${e.name}] failed:`, e.error),
});

// Wrap any async function
const tracedFetch = observe(fetch, { name: "fetch" });
```

## Configuration Reference

```ts
new Agent({
  // Required
  llm: BaseChatModel,           // LLM provider instance
  tools: Tool[],                // Available tools

  // Optional
  system_prompt: string | null, // System message (default: null)
  max_iterations: number,       // Loop limit (default: 200)
  require_done_tool: boolean,   // Require explicit completion (default: false)
  tool_choice: ToolChoice,      // "auto" | "required" | "none" (default: "auto")

  // Context management
  compaction: {
    enabled: boolean,           // Enable auto-compaction (default: true)
    threshold_ratio: number,    // Trigger at this % of context (default: 0.8)
  } | null,                     // null disables compaction (default: null)

  // Retries
  llm_max_retries: number,      // Retry attempts (default: 5)
  llm_retry_base_delay: number, // Base delay in seconds (default: 1.0)
  llm_retry_max_delay: number,  // Max delay in seconds (default: 60.0)
  retry: { enabled: boolean },  // Disable retry logic when false (default: true)

  // Advanced
  dependency_overrides: Map | Record, // DI overrides for testing
  pricing_provider: PricingProvider | null, // Optional pricing data
});
```

## Minimal Core Loop

If you want the bare for-loop (no retries, compaction, or ephemerals), use `CoreAgent`.

```ts
const agent = new CoreAgent({ llm, tools });
const result = await agent.query("do the thing");
```

## Raw Tools

If you don’t want the decorator, use `rawTool` with an explicit schema.

```ts
const echo = rawTool(
  { name: "echo", description: "Echo", parameters: { type: "object", properties: { text: { type: "string" } }, required: ["text"], additionalProperties: false } },
  async ({ text }) => `hi ${text}`,
);
```

## Examples

- [`examples/quick_start.ts`](examples/quick_start.ts) — minimal working example
- [`examples/claude_code.ts`](examples/claude_code.ts) — CLI agent with bash/read/write tools
- [`examples/dependency_injection.ts`](examples/dependency_injection.ts) — DI patterns

## Contributing

See [TESTING.md](TESTING.md) for how to run tests.

## License

MIT
