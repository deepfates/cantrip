# cantrip

A template for building your own agents. Clone it, learn from it, make it yours.

## What is an agent?

An agent is a loop. You give an LLM a set of tools, ask it a question, and it responds by either answering or asking to use a tool. If it asks for a tool, you run that tool and show it the result. Then it either answers, or asks for another tool. This continues until it's done.

```ts
while (true) {
  const response = await crystal.query(messages, tools);
  messages.push(response);
  if (!response.tool_calls) break;
  for (const call of response.tool_calls) {
    messages.push(await execute(call));
  }
}
```

That's the core of it. The crystal (LLM) decides what to do, the gates (tools) let it act, and the loop keeps going until there's nothing left to do.

## The vocabulary

Cantrip uses a specific vocabulary. The names come from the spec (SPEC.md).

- **Crystal** — a stateless LLM interface. You give it messages, it returns a response.
- **Gate** — a typed function the entity can call. Gates cross the boundary between the entity and the outside world.
- **Circle** — the entity's capability envelope: medium + gates + wards.
- **Medium** — the substrate the entity works in. A JS sandbox, a browser, or conversation (the default).
- **Ward** — a constraint on the circle: max turns, require done, max depth.
- **Cantrip** — the recipe: crystal + call + circle. Cast it on an intent to create an entity.
- **Call** — the system prompt and configuration. Immutable once constructed.
- **Intent** — the user's request. Appears as the first user message.
- **Entity** — the running instance. Created by casting a cantrip.
- **Loom** — the append-only execution record. A tree of turns.

## How does it know when to stop?

The `done` gate signals "I'm done, here's the answer." When the entity calls it, `TaskComplete` is thrown, which breaks the loop and returns the result.

```ts
const done = gate(
  "Signal that you've finished the task",
  async ({ message }: { message: string }) => {
    throw new TaskComplete(message);
  },
  { name: "done", params: { message: "string" } }
);
```

In a JS medium, this becomes `submit_answer(result)` — same mechanism, projected into the sandbox.

## Get started

```bash
gh repo create my-agent --template deepfates/cantrip
cd my-agent
bun install
bun run examples/04_cantrip.ts
```

## Learn by example

The examples build on each other. Work through them in order.

### The ingredients

**[`01_crystal.ts`](examples/01_crystal.ts)** — A crystal wraps an LLM. Messages in, response out. The simplest building block.

**[`02_gate.ts`](examples/02_gate.ts)** — A gate is a typed function the entity can call. Gates cross into the outside world.

**[`03_circle.ts`](examples/03_circle.ts)** — A circle = medium + gates + wards. Must have a done gate (CIRCLE-1) and at least one ward (CIRCLE-2).

**[`04_cantrip.ts`](examples/04_cantrip.ts)** — Crystal + call + circle = cantrip. Cast it on an intent, an entity arises. The full recipe.

**[`05_ward.ts`](examples/05_ward.ts)** — Wards constrain the circle. Multiple wards compose: most restrictive wins.

**[`06_providers.ts`](examples/06_providers.ts)** — Same cantrip, different crystal. Swap the crystal to use any LLM provider.

### Mediums

**[`07_conversation.ts`](examples/07_conversation.ts)** — No medium specified = conversation (tool-calling baseline). The crystal sees gates as tool calls.

**[`08_js_medium.ts`](examples/08_js_medium.ts)** — The entity works inside a QuickJS sandbox. Gates are projected as host functions. ONE medium per circle.

**[`09_browser_medium.ts`](examples/09_browser_medium.ts)** — The entity works inside a Taiko browser session. It writes Taiko code.

### Composition and memory

**[`10_composition.ts`](examples/10_composition.ts)** — Nested entities. The JS medium puts data outside the prompt; the entity explores via code.

**[`11_folding.ts`](examples/11_folding.ts)** — Compress older turns to keep the context window small. Original turns preserved in the loom.

### Full agents

**[`12_full_agent.ts`](examples/12_full_agent.ts)** — JS medium + filesystem gates. The code sandbox with host functions crossing into it.

**[`13_acp.ts`](examples/13_acp.ts)** — Agent Control Protocol adapter for editor integration (VS Code, Claude Desktop).

**[`14_recursive.ts`](examples/14_recursive.ts)** — Depth-limited self-spawning. Parent delegates subtasks to child entities via call_entity.

**[`15_research_entity.ts`](examples/15_research_entity.ts)** — The full-package capstone. ACP + jsBrowser medium + recursive children + memory management.

**[`16_familiar.ts`](examples/16_familiar.ts)** — The Familiar. A coordinator entity that constructs and casts child cantrips from code. Repo observation + delegation via cantrip construction.

## Directory structure

```
src/
├── crystal/          # The model — stateless query() interface + providers + tokens
├── circle/           # The environment — gates + wards + mediums
│   ├── circle.ts     # Circle = {medium, gates, wards}
│   ├── ward.ts       # Ward (max_turns, require_done, max_depth)
│   ├── medium.ts     # Medium interface
│   ├── medium/       # Medium implementations (js, browser, bash)
│   └── gate/         # Gate definitions + builtins (done, fs, repo, call_entity)
├── cantrip/          # The recipe — cantrip() and Entity
├── loom/             # The execution record — append-only turn tree, threads, folding
└── entity/           # Runtime support — events, errors, REPL, ACP adapter
```

## Builtin gates

**done** — Signals task completion. Required in every circle (CIRCLE-1). In a JS medium, projected as `submit_answer()`.

**Filesystem (`src/circle/gate/builtin/fs`)** — Sandboxed access: `read`, `write`, `edit`, `glob`, `bash`.

**Repo (`src/circle/gate/builtin/repo`)** — Read-only repository introspection: `repo_files`, `repo_read`, `repo_git_log`, `repo_git_status`, `repo_git_diff`. Path-jailed to repo root.

**call_entity / call_entity_batch** — Delegate to child entities. Depth-limited recursive spawning.

## Mediums

**JS (`src/circle/medium/js.ts`)** — QuickJS WASM sandbox. Gates projected as host functions. The entity writes JavaScript. Supports cantrip construction when configured with `cantrip: { crystals, mediums, gates }`.

**Browser (`src/circle/medium/browser.ts`)** — Headless browser via Taiko. The entity writes Taiko code.

**Bash (`src/circle/medium/bash.ts`)** — Shell execution medium.

**Conversation (default)** — No medium. The crystal sees gates as tool calls in natural language.

## Providers

```ts
import {
  ChatAnthropic,
  ChatOpenAI,
  ChatGoogle,
  ChatLMStudio,
  ChatOpenRouter,
} from "cantrip/crystal";
```

- **ChatLMStudio** — Local OpenAI-compatible server (`http://localhost:1234/v1` by default).
- **ChatOpenRouter** — OpenRouter API with attribution headers.
- All providers implement the `BaseChatModel` interface: `query(messages, tools?, tool_choice?)`.

## Agent Client Protocol (ACP)

Cantrip can serve agents over [Agent Client Protocol](https://github.com/agentclientprotocol/spec) for editor integration.

```json
{
  "acp.agents": [
    {
      "name": "cantrip",
      "command": "bun",
      "args": ["run", "examples/13_acp.ts"],
      "cwd": "${workspaceFolder}"
    }
  ]
}
```

## The philosophy

Most agent frameworks add layers between you and the model: planning systems, verification steps, output parsers, state machines. The idea behind cantrip is that you probably don't need most of that. LLMs already know how to reason and use tools. Your job is to give them good tools and get out of the way.

Start simple. Add complexity when you feel the pain, not before.

## Make it yours

Read the source. It's not much code. Change whatever doesn't fit your use case. Delete what you don't need. This is a starting point, not a dependency.

## License

MIT
