# Agent

Simple agentic loop with native tool calling.

## Quick Start

```ts
import { Agent } from "simple-agent";
import { ChatOpenAI } from "simple-agent/llm";
import { tool } from "simple-agent";

const add = tool(
  "Add two numbers",
  async ({ a, b }: { a: number; b: number }) => a + b,
  { name: "add", params: { a: "number", b: "number" } }
);

const agent = new Agent({
  llm: new ChatOpenAI({ model: "gpt-4o" }),
  tools: [add],
});

const result = await agent.query("What is 2 + 2?");
```

## Streaming Events

```ts
import { ToolCallEvent, ToolResultEvent, FinalResponseEvent } from "simple-agent/agent";

for await (const event of agent.query_stream("do something")) {
  if (event instanceof ToolCallEvent) {
    console.log(`Calling ${event.tool}`);
  } else if (event instanceof ToolResultEvent) {
    console.log(`${event.tool} returned: ${event.result}`);
  } else if (event instanceof FinalResponseEvent) {
    console.log(`Done: ${event.content}`);
  }
}
```

## Dependency Injection

```ts
import { Depends, tool } from "simple-agent";

function getDb() {
  return new Database();
}

const query = tool(
  "Query database",
  async ({ sql }: { sql: string }, deps) => {
    return deps.db.execute(sql);
  },
  {
    params: { sql: "string" },
    dependencies: { db: new Depends(getDb) },
  }
);
```

## Multi-turn Conversations

```ts
await agent.query("My name is Alice");
await agent.query("What's my name?");
agent.clear_history();
```

## Token Usage

```ts
const usage = await agent.get_usage();
console.log(usage.total_tokens);
```
