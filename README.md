# cantrip

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

The tools you give an agent define what it can do. An agent with `bash`, `read`, and `write` tools can interact with your filesystem. An agent with an `http` tool can make API calls. An agent with just `add` and `done` can do arithmetic. The tools are the agent's capabilities.

## Get started

This is a GitHub template. Clone it to start your own project:

```bash
gh repo create my-agent --template deepfates/cantrip
cd my-agent
bun install
bun run examples/quick_start.ts
```

## Learn by example

The examples build on each other. Work through them in order.

**[`core_loop.ts`](examples/core_loop.ts)** — The loop with a fake LLM that returns hardcoded responses. No API keys needed. Start here to see how the pieces fit together.

**[`quick_start.ts`](examples/quick_start.ts)** — A real agent using Claude. Has an `add` tool and a `done` tool. Your first working agent.

**[`batteries_off.ts`](examples/batteries_off.ts)** — The same agent but with the optional features (retries, ephemerals, compaction) turned off. Helps you see what's core vs. what's extra.

**[`chat.ts`](examples/chat.ts)** — An interactive terminal chat. Uses streaming to show tool calls as they happen. Includes a `think` tool that lets the model reason step by step.

**[`claude_code.ts`](examples/claude_code.ts)** — A coding agent with bash, read, write, edit, and glob tools. Shows how to sandbox filesystem access and inject dependencies into tools.

**[`dependency_injection.ts`](examples/dependency_injection.ts)** — How to give tools access to databases, API clients, or test mocks.

## Optional features

The `Agent` class includes some features you can turn on or off:

**Retries** — Automatically retry when the LLM returns rate limit errors or transient failures. On by default.

**Ephemerals** — Some tools produce large outputs (like screenshots) that eat up context. Mark a tool as `ephemeral: 3` to keep only its last 3 results in the conversation history.

**Compaction** — When the conversation gets too long, summarize it to free up context space. Configure with `compaction: { threshold_ratio: 0.8 }`.

If you don't need these, use `CoreAgent` instead, or disable them in `Agent`.

## Providers

```ts
import { ChatAnthropic, ChatOpenAI, ChatGoogle } from "cantrip/llm";
```

## The philosophy

Most agent frameworks add layers between you and the model: planning systems, verification steps, output parsers, state machines. The idea behind cantrip is that you probably don't need most of that. LLMs already know how to reason and use tools. Your job is to give them good tools and get out of the way.

Start simple. Add complexity when you feel the pain, not before. If you want the full argument, read [The Bitter Lesson of Agent Frameworks](https://browser-use.com/posts/bitter-lesson-agent-frameworks).

## Make it yours

Read the source. It's not much code. Change whatever doesn't fit your use case. Delete what you don't need. This is a starting point, not a dependency.

## License

MIT
