# 📜 cantrip 

A tiny agent loop you can actually understand, edit, and own.

- The loop is the agent. Everything else is optional.
- Tools are the product. Action space beats abstraction.
- Start simple, add reliability only when you feel the pain.

The loop:

```ts
while (true) {
  const response = await llm.invoke(messages, tools);
  if (!response.tool_calls) break;
  for (const call of response.tool_calls) {
    messages.push(await execute(call));
  }
}
```

This library wraps that loop with just enough to be practical: multi-provider LLM support, tool schemas, context management, streaming. Nothing more.

## Install

```bash
bun add cantrip
```

## Quick Start

```ts
import { Agent, TaskComplete, tool } from "cantrip";
import { ChatAnthropic } from "cantrip/llm";
import { z } from "zod";

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

const agent = new Agent({
  llm: new ChatAnthropic({ model: "claude-sonnet-4-20250514" }),
  tools: [add, done],
});

const answer = await agent.query("What is 2 + 3?");
```

## What the loop does

1. Your message gets added to the conversation history
2. The LLM is called with the history and available tools
3. If the LLM returns tool calls, each one is executed and results added to history
4. Repeat until the LLM responds without tool calls (or hits max iterations)

That's the architecture.

## Layers

**CoreAgent** — the bare loop:

```ts
import { CoreAgent, rawTool } from "cantrip";

const agent = new CoreAgent({ llm, tools: [add] });
const result = await agent.query("What is 2 + 3?");
```

**Agent** — adds retries, context management, token tracking:

```ts
const agent = new Agent({
  llm,
  tools,
  retry: { enabled: true },
  compaction: { threshold_ratio: 0.8 },
});
```

Pick the layer you need and build upward.

## Tools

Three ways to define schemas:

**Zod (recommended):**

```ts
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

**Fluent builder:**

```ts
import { ToolSchema } from "cantrip";

const schema = ToolSchema.create()
  .addString("query")
  .addInteger("limit", { optional: true })
  .build();
```

**Params shorthand:**

```ts
const search = tool("Search", handler, {
  name: "search",
  params: { query: "string", limit: "integer?" },
});
```

## Context Management

**Ephemeral messages** — keep only last N results from repetitive tools:

```ts
const screenshot = tool(
  "Take screenshot",
  async () => takeScreenshotBase64(),
  { name: "screenshot", ephemeral: 3 }
);
```

**Compaction** — summarize conversation when context exceeds threshold:

```ts
const agent = new Agent({
  llm,
  tools,
  compaction: { threshold_ratio: 0.8 },
});
```

## Explicit Completion

For complex workflows, require explicit completion:

```ts
const agent = new Agent({
  llm,
  tools: [...yourTools, done],
  require_done_tool: true,
});
```

`TaskComplete` is a control-flow escape hatch: throw it from any tool to end the loop.

## Providers

```ts
import {
  ChatAnthropic,
  ChatOpenAI,
  ChatGoogle,
} from "cantrip/llm";
```

## Dependency Injection

```ts
import { Depends, tool } from "cantrip";

const query = tool(
  "Query database",
  async ({ sql }, deps) => deps.db.execute(sql),
  {
    name: "query",
    params: { sql: "string" },
    dependencies: { db: new Depends(() => new Database(process.env.DB_URL)) },
  }
);

// Override for testing
const result = await query.execute({ sql: "SELECT 1" }, { db: () => mockDb });
```

## Streaming

```ts
import { ToolCallEvent, ToolResultEvent, FinalResponseEvent } from "cantrip/agent";

for await (const event of agent.query_stream("Do something")) {
  if (event instanceof ToolCallEvent) {
    console.log(`Calling: ${event.tool}`);
  } else if (event instanceof FinalResponseEvent) {
    console.log(`Done: ${event.content}`);
  }
}
```

## Observability

```ts
import { observe, setObserver } from "cantrip";

setObserver({
  onStart: (e) => console.log(`[${e.name}] started`),
  onEnd: (e) => console.log(`[${e.name}] completed in ${e.duration_ms}ms`),
  onError: (e) => console.error(`[${e.name}] failed:`, e.error),
});
```

## Configuration

```ts
new Agent({
  // Required
  llm: BaseChatModel,
  tools: Tool[],

  // Optional
  system_prompt: string | null,
  max_iterations: number,             // default: 200
  require_done_tool: boolean,         // default: false
  tool_choice: ToolChoice,            // default: "auto"

  // Context
  compaction: { threshold_ratio: number } | null,
  ephemerals: { enabled: boolean },

  // Retries
  llm_max_retries: number,            // default: 5
  retry: { enabled: boolean },

  // Testing
  dependency_overrides: Map | Record,
});
```

## Examples

- [`examples/quick_start.ts`](examples/quick_start.ts) — minimal example
- [`examples/claude_code.ts`](examples/claude_code.ts) — CLI agent with bash/read/write
- [`examples/chat.ts`](examples/chat.ts) — interactive chat with think tool
- [`examples/core_loop.ts`](examples/core_loop.ts) — CoreAgent + rawTool
- [`examples/batteries_off.ts`](examples/batteries_off.ts) — Agent with extras disabled

## Background

The most successful agents (Claude Code, Cursor, etc.) converged on this architecture: a loop with tools. No planning modules, no verification layers. This library is that loop, with just enough around it to be practical.

Inspired by [browser-use/agent-sdk](https://github.com/browser-use/agent-sdk).
## License

MIT
