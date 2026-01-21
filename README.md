# simple-agent

_An agent is just a for-loop._

The simplest possible agent framework in TypeScript + Bun. No abstractions. No magic. Just a for-loop of tool calls.

## Install

```bash
bun install
```

## Quick Start

```ts
import { Agent, TaskComplete, tool } from "simple-agent";
import { ChatAnthropic } from "simple-agent/llm";

const add = tool(
  "Add two numbers",
  async ({ a, b }: { a: number; b: number }) => a + b,
  {
    schema: {
      type: "object",
      properties: {
        a: { type: "integer" },
        b: { type: "integer" },
      },
      required: ["a", "b"],
      additionalProperties: false,
    },
  }
);

const done = tool(
  "Signal task completion",
  async ({ message }: { message: string }) => {
    throw new TaskComplete(message);
  },
  {
    schema: {
      type: "object",
      properties: { message: { type: "string" } },
      required: ["message"],
      additionalProperties: false,
    },
  }
);

const agent = new Agent({
  llm: new ChatAnthropic({ model: "claude-sonnet-4-20250514" }),
  tools: [add, done],
});

const result = await agent.query("What is 2 + 3?");
console.log(result);
```

## Philosophy

**The Bitter Lesson:** All the value is in the RL'd model, not your 10,000 lines of abstractions.

Agent frameworks fail not because models are weak, but because their action spaces are incomplete. Give the LLM as much freedom as possible, then vibe-restrict based on evals.

## Features

### Done Tool Pattern

Force explicit completion:

```ts
const done = tool(
  "Signal completion",
  async ({ message }: { message: string }) => {
    throw new TaskComplete(message);
  },
  {
    schema: {
      type: "object",
      properties: { message: { type: "string" } },
      required: ["message"],
      additionalProperties: false,
    },
  }
);

const agent = new Agent({
  llm,
  tools: [...tools, done],
  require_done_tool: true,
});
```

### Ephemeral Messages

Large tool outputs blow up context. Keep only the last N:

```ts
const get_state = tool(
  "Get browser state",
  async () => "...",
  { ephemeral: 3 }
);
```

### Simple LLM Primitives

Provider adapters are thin wrappers:

```ts
import { ChatAnthropic, ChatOpenAI, ChatGoogle } from "simple-agent/llm";

new Agent({ llm: new ChatAnthropic({ model: "claude-sonnet-4-20250514" }), tools });
new Agent({ llm: new ChatOpenAI({ model: "gpt-4o" }), tools });
new Agent({ llm: new ChatGoogle({ model: "gemini-2.0-flash" }), tools });
```

### Context Compaction

```ts
import { CompactionService } from "simple-agent/agent";

const agent = new Agent({
  llm,
  tools,
  compaction: { threshold_ratio: 0.8 },
});
```

### Dependency Injection

```ts
import { Depends, tool } from "simple-agent";

function getDb() {
  return new Database();
}

const query = tool(
  "Query database",
  async ({ sql }: { sql: string }, deps) => {
    const db = deps.db as Database;
    return db.query(sql);
  },
  {
    schema: {
      type: "object",
      properties: { sql: { type: "string" } },
      required: ["sql"],
      additionalProperties: false,
    },
    dependencies: { db: new Depends(getDb) },
  }
);
```

### Streaming Events

```ts
import { ToolCallEvent, ToolResultEvent, FinalResponseEvent } from "simple-agent/agent";

for await (const event of agent.query_stream("do something")) {
  if (event instanceof ToolCallEvent) {
    console.log(`Calling ${event.tool}`);
  } else if (event instanceof ToolResultEvent) {
    console.log(`${event.tool} -> ${event.result.slice(0, 50)}`);
  } else if (event instanceof FinalResponseEvent) {
    console.log(`Done: ${event.content}`);
  }
}
```

## Examples

- `examples/quick_start.ts`
- `examples/claude_code.ts`

## Testing

See `TESTING.md`.

## License

MIT
