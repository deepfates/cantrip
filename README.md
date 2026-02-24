# cantrip

> "The cantrips have been spoken. The patterns of force are aligned. Now it is up to your machine."
> — Gargoyles: Reawakening

A framework for building autonomous LLM entities with action capabilities. Give an LLM a goal and an environment, watch it work toward completion.

## What is a cantrip?

A **cantrip** is a composable unit that combines:
- **Crystal** - An LLM (cognition)
- **Medium** - An interactive environment (action)  
- **Circle** - A control loop (autonomy)

Together they create an **entity** that can reason, act, observe, and adapt.

---

## Core Concepts

### 🔮 Crystal (Cognition)

A **crystal** is an interface to an LLM. It takes messages and tools, returns responses with tool calls.

```typescript
import { crystal } from "cantrip/crystal";

const haiku = crystal({
  model: "anthropic/claude-3.5-haiku",
  temperature: 0.7
});
```

Crystals are stateless API wrappers. We use OpenRouter for model access.

---

### 🌊 Medium (Action)

A **medium** is an **interactive evaluation environment** where the model's utterances are executed:

- **Bash medium**: A shell session where the model writes commands
- **JavaScript medium**: A JS runtime where the model writes code
- **Python medium**: A Python interpreter where the model writes Python
- **Browser medium**: A headless browser where the model controls the page

**Key insight:** A medium provides a REPL/interpreter/session, NOT individual tools.

The model uses tools *within* the medium:
- In bash: Uses git, curl, ffmpeg, jq by writing shell commands
- In Python: Uses requests, pandas, numpy by writing Python code
- In JavaScript: Uses fetch, fs, child_process by writing JS code

```typescript
import { bash } from "cantrip/circle/medium";

// Creates a bash session
const shell = bash({ cwd: "/project" });

// Model can now execute: git status, curl http://..., etc.
```

---

### ⭕ Circle (Control)

A **circle** is the entity loop that connects crystal and medium:

```
Intent → Crystal → Assistant Response → Medium Execution → Observations → Crystal → ...
```

The loop continues until:
- **Gate opens**: Entity signals completion (e.g., calls \`submit_answer()\`)
- **Ward violated**: Safety limit reached (max turns, timeout, cost)

```typescript
import { circle } from "cantrip/circle";
import { done } from "cantrip/circle/gate";

const agent = circle({
  crystal: haiku,
  medium: bash({ cwd: "." }),
  gates: [done()],  // Provides submit_answer() tool
  wards: [{ max_turns: 10 }]
});
```

**Gates** (success conditions):
- \`done()\` - Entity calls \`submit_answer(result)\` when finished
- Custom gates - Check for specific conditions

**Wards** (safety limits):
- \`max_turns\` - Limit loop iterations
- \`max_cost\` - Limit API spending
- \`max_time\` - Timeout in milliseconds

---

### 🪄 Cantrip (Composition)

Put it all together:

```typescript
import { cantrip, cast } from "cantrip";
import { crystal } from "cantrip/crystal";
import { bash } from "cantrip/circle/medium";
import { done } from "cantrip/circle/gate";

const researcher = cantrip({
  crystal: crystal({ model: "anthropic/claude-3.5-sonnet" }),
  call: {
    system: "You research topics using bash tools. Use curl, grep, etc."
  },
  circle: {
    medium: bash(),
    gates: [done()],
    wards: [{ max_turns: 20 }]
  }
});

// Cast the cantrip with an intent
const result = await cast(researcher, "Research TypeScript compiler architecture");
console.log(result);
```

**Leaf cantrip** (no circle - single LLM call):

```typescript
const analyzer = cantrip({
  crystal: crystal({ model: "anthropic/claude-3.5-haiku" }),
  call: { system: "You analyze code for bugs" }
});

const bugs = await cast(analyzer, "Here's my function: " + code);
```

---

## 🪆 The Familiar (Meta-Circular Cantrips)

The **Familiar** is a special cantrip that runs in a JS medium with the ability to create and cast child cantrips:

```typescript
import { familiar } from "cantrip";

const myFamiliar = familiar({
  crystal: crystal({ model: "anthropic/claude-3.5-sonnet" }),
  workspace: "/project",
  memory: ".cantrip/loom.jsonl"
});

// The Familiar can coordinate complex tasks by creating specialized children
await cast(myFamiliar, "Analyze the codebase and run the test suite");
```

Inside the Familiar's JS medium, it has access to:
- \`cantrip(config)\` - Create child cantrips
- \`cast(handle, intent)\` - Execute children
- \`repo_files()\`, \`repo_read()\` - Observe the repository
- Persistent memory across sessions

This enables **hierarchical task decomposition**: The Familiar breaks down your request into subtasks, creates specialized cantrips for each, coordinates their execution, and synthesizes results.

---

## Available Mediums

### Bash
Execute shell commands with full access to CLI tools.

```typescript
bash({ cwd: "/path", env: { KEY: "value" } })
```

Use: git operations, file manipulation, curl requests, ffmpeg processing

### JavaScript (QuickJS)
Execute JavaScript in a sandboxed runtime.

```typescript
js({ 
  cwd: "/path",
  host_functions: { /* custom functions */ }
})
```

Use: Data processing, API calls, custom logic

### Browser
Control a headless browser with Puppeteer.

```typescript
browser({ 
  headless: true,
  viewport: { width: 1280, height: 720 }
})
```

Use: Web scraping, testing, automation

### Python (Coming Soon)
Execute Python code with access to the Python ecosystem.

### More Mediums

Any interactive environment can be a medium:
- **SQL REPL** - Database queries
- **Frida** - Dynamic instrumentation
- **GDB** - Interactive debugging
- **Redis CLI** - Cache operations
- **Custom DSLs** - Your domain-specific language

---

## Message Format

Cantrip uses the standard OpenAI message format:

```typescript
type Message = 
  | { role: "system", content: string }
  | { role: "user", content: string }
  | { role: "assistant", content: string, tool_calls?: ToolCall[] }
  | { role: "tool", tool_call_id: string, content: string }
```

This ensures compatibility and makes it easy to reason about conversation state.

---

## Architecture Philosophy

**Separation of Concerns:**
- **Crystal** = Cognition (stateless LLM interface)
- **Medium** = Action (stateful execution environment)
- **Circle** = Control (loop with gates and wards)

**Composability:**
- Cantrips can create other cantrips
- Mediums can spawn subprocesses using other mediums
- TypeScript cantrip → Python cantrip → Bash commands

**Polyglot by Design:**
- Reference implementation in TypeScript
- Concepts are language-agnostic
- Each language can implement its native medium best
- Cross-language communication via subprocess/IPC

---

## Examples

### Research Agent
```typescript
const researcher = cantrip({
  crystal: sonnet,
  call: { system: "Research topics using bash tools" },
  circle: {
    medium: bash(),
    gates: [done()],
    wards: [{ max_turns: 20 }]
  }
});

await cast(researcher, "What are the latest trends in WebAssembly?");
```

### Code Analyzer
```typescript
const analyzer = cantrip({
  crystal: haiku,
  call: { 
    system: "Analyze code for security vulnerabilities",
    tools: [/* custom tools */]
  }
});

await cast(analyzer, "Review this authentication module: " + code);
```

### Browser Automation
```typescript
const scraper = cantrip({
  crystal: haiku,
  call: { system: "Extract data from websites" },
  circle: {
    medium: browser({ headless: true }),
    gates: [done()],
    wards: [{ max_turns: 15, max_time: 60000 }]
  }
});

await cast(scraper, "Get the top HN stories with scores > 100");
```

---

## Installation

```bash
npm install cantrip
```

Set your OpenRouter API key:
```bash
export OPENROUTER_API_KEY="sk-..."
```

---

## Implementation in Other Languages

This is the reference TypeScript implementation. The concepts are designed to be language-agnostic:

**Python implementation** would:
- Use \`requests\` for Crystal (OpenRouter)
- Native Python medium via \`exec()\`
- Other mediums via subprocess
- Same message format and control flow

**Rust implementation** would:
- Use \`reqwest\` for Crystal
- Embed Lua via \`rlua\` for scripting medium
- Other mediums via subprocess or FFI
- Strong typing for gates/wards

The SPEC.md provides a formal specification for implementing cantrip in any language.

---

## Why "Cantrip"?

In D&D, a cantrip is a simple spell that can be cast repeatedly without cost. Here, a cantrip is a reusable pattern for creating LLM entities - configure once, cast many times, compose into larger spells.

---

## License

MIT
