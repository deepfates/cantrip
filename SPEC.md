# Cantrip

>"The cantrips have been spoken. The patterns of force are aligned. Now it is up to your machine."
>
> — Gargoyles: Reawakening (1995)

**Version**: 0.2.0
**Status**: Draft — behavioral rules for implementation

## Introduction

A cantrip is a spell. In fantasy games, it refers to the simple starter spells that come in your spellbook at level 1. The etymology is thought to be related to Gaelic "Canntaireachd", a piper's mnemonic chant. It's a loop of language.

This is a starter spellbook of your own. It describes a method for creating spells using the tools of modern summoning: a language model, a computer, and a prompt. It's language loops all the way down.

A language model takes text in and gives text back. One pass — no memory, no consequences. To make it do things, you close the loop: take the model's output, run it in some kind of environment, and let it observe the effects. A chat interface is the simplest loop — but conversation alone lacks ontological hardness. Attach a verifiable environment — a shell, a REPL, a browser, a prover — and feed the result back as input. Now what the model writes has consequences it can predict and adjust for. The environment pushes back: code runs or crashes, files exist or don't, tests pass or fail. Turn by turn, the model accumulates experience. It starts doing things its designers never specifically enumerated, because the action space is a programming language and programming languages are compositional.

That's the shape of this library: call and response. You draw a circle, you speak into it, something answers. Each turn through the loop brings the model closer to the task or reveals why the task is harder than it looked.

This spellbook gives names to the parts of that loop. Three are fundamental: the **LLM** (the model), the **identity** (the configuration that shapes it), and the **circle** (the environment it acts in). The LLM thinks. The identity tells it who it is. The circle is where it acts. Everything else is what happens when you put those three together and let the loop run.

The circle has a **medium** — the substrate the entity works *in*. Think of it like an artist's medium: oil, marble, code. **Gates** cross the circle's boundary from outside — reading files, making HTTP requests, spawning child entities. **Wards** restrict what the entity can do — turn limits, resource caps, scope constraints. The entity's action space is the union of the medium's primitives and the registered gates, minus whatever the wards restrict.

Why new names? The existing ones — "agent," "tool," "environment" — are overloaded. They carry assumptions from specific frameworks and mean different things to different people. These terms are precise within this system: each one maps to exactly one concept, and the concepts compose cleanly from a chat interface all the way up to a multi-agent system where parent entities delegate to children.

The same pattern works at every scale. The simplest cantrip is an LLM in a loop with one gate (`done`) and no wards beyond a turn limit. The most complex is a tree of entities with recursive composition, a loom feeding comparative reinforcement learning, and circles nested inside circles. Same vocabulary, different configuration. Cantrip describes behavior, not technology. Any implementation that passes the accompanying test suite (`tests.yaml`) is a valid cantrip. Terms are defined in context as they appear; the Glossary at the end is there for quick reference.

---

## Chapter 1: The Loop

Everything in this document — every term, every rule, every architectural decision — exists to give structure to one idea: a model acting in a loop with an environment. The loop is the foundation. Start here.

### 1.1 The turn

Each cycle through the loop is called a **turn**. A turn has two halves.

First, the **entity** — the running instance of the model inside the loop — produces an **utterance**: text that may contain executable code or structured calls to the environment. Then the **circle** — the environment — executes what the entity wrote and produces an **observation**: a single composite object containing an ordered list of results, one entry per gate call, plus sandbox output if applicable. The observation feeds into the next turn as one unit. State accumulates.

> **LOOP-1**: The loop MUST alternate between entity utterances and circle observations. Two consecutive entity utterances without an intervening observation MUST NOT occur.

This strict alternation is what makes the loop a loop and not a monologue. The entity acts, the world responds, the entity acts again with the world's response in hand.

Two terms before we move on. The script that defines the loop — which model, which configuration, which environment — is called a **cantrip**. The goal the entity is pursuing is called an **intent**. Both get their own treatment later. For now, what matters is the cycle: act, observe, repeat.

Why does the loop matter beyond practical utility? Because closing the loop is what transforms a predictor into an agent. When outputs influence subsequent inputs, the system transitions from passive prediction to world-shaping action. The model's completions change the environment, the changed environment changes the next prompt, and the model adjusts. The loop is not just an engineering pattern. It is the mechanism by which a generative model becomes something that acts.

### 1.2 What the entity perceives

On every turn, the entity needs to know two things: what it's supposed to do, and what has happened so far.

The **identity** — the immutable configuration that shapes the model's behavior — and the **intent** — the goal — are always present. Think of them as the entity's fixed orientation: who it is, and what it's after. Those never change.

Everything beyond that is mediated by the circle. In the simplest design, the circle presents the full history of prior turns as a growing message list. In a code circle, the entity can access state through code instead: reading variables, querying data structures, inspecting files that persist between turns. Both are valid. What the entity sees is the circle's decision.

> **LOOP-5**: The entity MUST receive the identity and the intent on every turn. How prior turns are presented — as a message history, as program state, or as a combination — is determined by the circle's design. The circle mediates what the entity perceives.

### 1.3 Termination and truncation

Every loop ends. The question is how, and the answer matters more than you might expect.

**Terminated** means the entity called the `done` gate — a special exit point that signals "I believe the task is complete." The entity chose to stop. In a code circle, the done gate is projected into the medium as `submit_answer` — the entity calls `submit_answer(result)` in code, and the medium translates this into the done gate on the entity's behalf.

**Truncated** means a **ward** cut the entity off. A ward is a restriction on the loop — a maximum number of turns, a timeout, a resource limit. The environment chose to stop. The entity was interrupted, not finished.

> **LOOP-2**: The loop MUST terminate. Every cantrip MUST have at least one termination condition (a `done` gate, or text-only response when `require_done_tool` is false) AND at least one truncation condition (a max turns ward).

> **LOOP-3**: When the `done` gate is called, the loop MUST stop after processing that gate. Any remaining gate calls in the same utterance MAY be skipped.

> **LOOP-4**: When a ward triggers truncation, the loop MUST stop. The implementation SHOULD generate a summary of what was accomplished before the entity was cut off.

The cantrip's `require_done_tool` flag controls what happens when the entity produces a text-only response — no code, no gate calls, just words. When false (the default), a text-only response terminates the loop. When true, only an explicit `done` gate call terminates.

> **LOOP-6**: If `require_done_tool` is false (default) and the entity produces a text-only response (no gate calls), the loop MUST treat that as implicit termination. If `require_done_tool` is true, a text-only response MUST NOT terminate the loop — only a `done` gate call terminates.

> **LOOP-7**: If a `done` gate call is malformed (missing required arguments) or returns an error, the loop MUST NOT mark the turn as terminated. The failure MUST be returned as an observation and normal ward/truncation rules continue to apply.

Why does the terminated/truncated distinction matter? Because it travels with the data. A terminated thread is a completed episode — training data with a natural endpoint. A truncated thread is an interrupted episode — the entity's final state shouldn't be treated as a conclusion because it wasn't one. Implementations MUST record which occurred.

### 1.4 The cantrip, the intent, and the entity

Three terms have been floating through this chapter. Now they get pinned down.

A **cantrip** is the script that produces the loop. It binds an LLM to a circle through an identity — which model, which configuration, which environment. A cantrip is a value, not a running process. You write it once and cast it many times.

> **CANTRIP-1**: A cantrip MUST contain an LLM, an identity, and a circle. Missing any of these is invalid.

> **CANTRIP-2**: A cantrip is a value. It MUST be reusable — casting it multiple times on different intents MUST produce independent entities.

An **intent** is the reason the loop runs — the goal, the task, the thing the entity is trying to achieve. Same cantrip, different intent, different episode.

> **INTENT-1**: The intent MUST be provided when casting a cantrip. A cantrip cannot be cast without an intent.

> **INTENT-2**: The intent MUST appear as the first user message in the entity's context, after the system prompt (if any).

> **INTENT-3**: The intent is immutable for the lifetime of a cast. The entity cannot change its own intent mid-episode. A summoned entity may receive new intents as subsequent casts (ENTITY-5).

And the **entity** is what appears when you cast a cantrip on an intent and the loop starts running. This is the one that's hard to pin down, because you don't build it — it arises.

Watch what happens after a few turns.

The LLM's output on turn twelve doesn't look like its output on turn one. It's referencing variables it created on turn four. It's working around an error it hit on turn seven. It's pursuing a strategy that emerged from something it noticed on turn nine — a pattern in the data that nobody told it to look for. The identity didn't ask for this strategy. The circle didn't suggest it. It appeared in the space between them, born from the accumulation of action and observation.

This is the entity. Not a thing you built — a thing that arose. The LLM is the same LLM it was before the loop started. The identity hasn't changed. The circle is just an environment, doing what environments do. But the process running through all three of them has developed something that looks uncomfortably like perspective. It has context. It has momentum. It has preferences shaped by what it's tried and what worked.

You didn't design the entity. You designed the LLM, the identity, and the circle. The entity is what happened when you put them together and let the loop run.

It will exist for as long as the loop runs. When the loop stops — task complete, budget exhausted, ward triggered — the entity is gone. The LLM remains, unchanged. The circle can be wiped or preserved. But the entity, that particular accumulation of context and strategy and in-context learning, is over. It lived in the loop and the loop is done.

Unless you recorded it. But that's a later chapter.

> **ENTITY-1**: An entity MUST be produced by a cantrip — either by casting (one-shot) or by summoning (persistent). There is no other way to create an entity.

> **ENTITY-2**: Each entity MUST have a unique ID. Implementations MUST auto-generate a unique entity ID if one is not provided by the caller.

> **ENTITY-3**: An entity's state MUST grow monotonically within a thread (modulo folding, which is a view transformation, not deletion — see Chapter 6).

> **ENTITY-4**: When an entity terminates or is truncated, its thread persists in the loom. The entity ceases but its record endures.

Summoning a cantrip produces a persistent entity. The initial intent starts the loop. When the loop completes — done or truncated — the entity persists. You can provide another intent as a new cast, and the loop resumes with accumulated state.

Casting is a convenience: summon, run one intent, return the result, discard the entity. Most examples in this document describe casting, because most tasks are one-shot. But the underlying mechanism is always summoning — casting is just summoning with automatic cleanup.

> **ENTITY-5**: A summoned entity persists after its loop completes. It MAY receive additional intents as new casts. State accumulates across all casts.

> **ENTITY-6**: Summoning a cantrip multiple times MUST produce independent entities, just as casting does (CANTRIP-2).

The LLM, the identity, and the circle each have their own chapters. The entity does not, because the entity is not a component you configure. It is what emerges from the components you did configure, once the loop begins.

### 1.5 The four temporal levels

Four verbs describe what happens in this system, and they operate at four distinct timescales.

**Query** is the atomic unit. One round-trip to the LLM: messages in, response out. The LLM is stateless, so each query is independent.

**Turn** is one cycle of the loop. The entity produces an utterance, the circle executes it and returns an observation. A turn is the atom of experience — the smallest unit that has both action and consequence.

**Cast** is one complete episode. A cantrip is cast on an intent, the loop runs until `done` or a ward triggers, and a result comes back.

**Summon** creates a persistent entity. The entity survives the completion of its first intent. You can send it additional intents, and the loop resumes with accumulated state.

These nest cleanly: a summon contains one or more casts, a cast contains one or more turns, a turn contains one or more queries. The nesting is strict — a query never spans turns, a turn never spans casts.

### 1.6 The RL correspondence

If you know reinforcement learning, this table shows how the vocabulary maps. If you don't, skip ahead — the spec teaches everything you need without it. The mapping is structural, not formal — these are parallels that help you reason about the system, not mathematical equivalences.

| RL concept | Cantrip equivalent | Notes |
|-----------|-------------------|-------|
| Policy | LLM + Identity | Frozen weights conditioned by immutable identity |
| Goal specification | Intent | The desire that shapes which actions are good |
| State s | Circle state | Accessed through gates |
| Action a | Code the entity writes | A = M ∪ G − W |
| Observation o | Gate return values + sandbox output | Rich, unstructured |
| Reward r | Implicit or explicit | Gate success/failure; verifier scores; thread ranking |
| Terminated | `done` gate called | Entity chose to stop |
| Truncated | Ward triggered | Environment chose to stop |
| Trajectory | Thread | One root-to-leaf path through the loom |
| Episode | Cast | One cast: intent in, result out |
| Replay buffer | Loom | Tree structure provides comparative RL data |
| Environment reset | New entity, clean circle | Forking is NOT a reset — it continues from prior state |

The loom's relationship to modern RL methods is developed fully in Chapter 6.

### 1.7 A complete example

All the pieces in one place. A file-processing task: count the words in every `.txt` file in a directory and report the total.

**The cantrip.** LLM: any model that supports tool calling. Identity: "You are a file-processing assistant. Use code to solve tasks efficiently." Circle: a code medium with three gates — `read(path) -> string`, `list_dir(path) -> string[]`, and `done(answer)` — a ward of max 10 turns, and `require_done_tool: true`. Filesystem root: `/data`.

**The intent.** "Count the total number of words across all .txt files in /data and return the count."

**Turn 1.** The entity appears, receives identity and intent, and produces:
```
const files = list_dir("/data");
```
Observation: `GateCallRecord { gate_name: "list_dir", arguments: '{"path":"/data"}', result: '["a.txt", "b.txt", "c.txt"]', is_error: false }`.

**Turn 2.** The entity reads all files:
```
const a = read("/data/a.txt");
const b = read("/data/b.txt");
const c = read("/data/c.txt");
```
Three `GateCallRecord` objects, each with `is_error: false` and file contents.

**Turn 3.** The entity counts and terminates:
```
const total = [a, b, c]
  .map(text => text.split(/\s+/).filter(w => w.length > 0).length)
  .reduce((sum, n) => sum + n, 0);
done(total);
```
Loop terminates with result 1547.

**The loom.** Three turns, one thread. Each turn records token usage, duration, utterance, and observation. The thread is terminated — a complete episode usable as training data, a debugging trace, or a template for forking.

**Error as steering.** Same cantrip, but `/data/b.txt` does not exist. Turn 2's observation for `b` returns `is_error: true` with `'ENOENT: no such file or directory'`. Turn 3: the entity sees the error and adapts — counts only `a` and `c`, reports `{ total: 1200, note: "b.txt not found, counted 2 of 3 files" }`. The error did not stop the entity. It steered it.

---

## Chapter 2: The LLM

The LLM is the model. You send it messages, it sends back a response. That is the entire interface — and the simplicity is the point.

An LLM does not act on its own. It has no memory between queries, no persistent state. You send it a list of messages and it sends back text, structured gate calls, or both. Then it's done. The next time you query it, you must send everything again. The LLM does not remember that there was a last time.

> **LLM-1**: An LLM MUST be stateless. Given the same messages and tool definitions, it SHOULD produce similar output (modulo sampling). It MUST NOT maintain internal state between queries.

This statelessness is the contract, not a limitation. Everything that makes an entity seem to learn across turns comes from the loop feeding the LLM's own prior output back as input. The learning lives in the loop, not in the LLM.

### 2.1 The LLM contract

```
llm.query(messages: Message[], tools?: ToolDefinition[], tool_choice?: ToolChoice, extra?: Record<string, unknown>) -> Response
```

The inputs:
- `messages` — an ordered list of messages (system, user, assistant, tool).
- `tools` — an optional list of gate definitions, expressed as JSON Schema.
- `tool_choice` — controls whether the LLM must use gates ("required"), may use them ("auto"), or must not ("none").
- `extra` — optional provider-specific parameters passed through to the underlying API.

The response contains:
- `content` — text output (may be null if the LLM only made gate calls)
- `tool_calls` — an optional list of gate invocations, each with an ID, gate name, and JSON arguments
- `usage` — token counts (prompt, completion, cached)
- `thinking` — optional reasoning trace (for models that support extended thinking)

> **LLM-2**: An LLM MUST accept messages up to its provider's context limit. When input exceeds that limit, the LLM SHOULD return a structured error (not silently truncate). In practice, context limit errors may come from the provider API rather than from a pre-check — folding (§6.8) is the primary mechanism for staying within limits.

> **LLM-3**: An LLM MUST return at least one of `content` or `tool_calls`. A response with neither is invalid.

> **LLM-4**: Each `tool_call` MUST include a unique ID, the gate name, and arguments as a JSON string.

> **LLM-5**: If `tool_choice` is "required", the LLM MUST return at least one tool call. If the provider doesn't support forcing tool use, the implementation SHOULD simulate it (e.g., by re-prompting). Implementations MAY rely on provider-native support for forced tool use where available.

### 2.2 The swap

Take a working cantrip and replace the LLM. Keep everything else — the circle, the identity, the gates, the wards, the intent. The entity that appears behaves differently. It reasons differently, makes different mistakes, pursues different strategies. The LLM is the one component you swap to change how the entity thinks without changing what it can do or where it acts.

### 2.3 Provider implementations

In practice, LLMs come from different providers with different APIs. The spec requires support for at least: **Anthropic** (Claude), **OpenAI** (GPT), **Google** (Gemini), **OpenRouter** (proxy), and **Local** (Ollama, vLLM, any OpenAI-compatible endpoint).

> **LLM-6**: Provider implementations MUST normalize responses to the common LLM contract. Provider-specific fields MAY be preserved as metadata but MUST NOT be required by consumers.

> **LLM-7**: In providers that require tool-call/result pairing, implementations MUST preserve call-result linkage exactly (including tool call IDs and ordering). Adapters MUST NOT emit tool-result messages unless the preceding assistant message contained matching tool calls.

---

## Chapter 3: The Identity

The LLM is a function. The identity is what you pass to it — or more precisely, the part that stays the same every time you pass it. The identity is everything that shapes the LLM's behavior before any intent arrives.

> **IDENTITY-1**: The identity MUST be set at cantrip construction time and MUST NOT change afterward.

### 3.1 What the identity contains

The identity is the union of two things:

1. **System prompt** — persona, behavioral directives, domain knowledge.
2. **Hyperparameters** — temperature, top_p, max_tokens, stop sequences, sampling configuration.

The LLM needs to know what gates are available — but that knowledge comes from the circle, not the identity. The circle registers gates, executes them, and presents them to the LLM as tool definitions at query time. The identity stays small and separable: the same identity can work in different circles with different gate sets.

> **IDENTITY-3**: Gate definitions are the circle's responsibility. The circle MUST present its registered gates to the LLM as tool definitions at query time. The identity carries rendered gate definitions produced by the circle for transport convenience, but the circle remains the authority for what gates exist. The circle — not the identity — registers, executes, and presents gates.

### 3.2 Immutability and identity

The identity is fixed. You can create a new cantrip with a different identity, but you can't mutate an existing one. This gives you clean axes of variation:

Same LLM + different identity = different entity behavior. Same LLM + same identity + different circle = different capabilities. Same everything + different intent = different episode.

> **IDENTITY-2**: If a system prompt is provided, it MUST be the first message in every context sent to the LLM. It MUST be present in every query, unchanged.

### 3.3 What the identity is not

Context belongs in the environment, not in the prompt. Dynamic context — retrieved documents, injected state, programmatic insertions that change per turn — is circle state, accessed through gates. A cantrip that processes a thousand documents places them in the circle as data the entity can read, query, and navigate through code. The identity tells the entity who it is. The circle contains what it works with. The identity doesn't grow. The circle does.

### 3.4 The identity in the loom

> **IDENTITY-4**: The identity MUST be stored in the loom as the root context. Every thread starts from the same identity.

> **IDENTITY-5**: Folding (context compression) MUST NOT alter the identity. The entity always retains its full identity. Only the trajectory (turns) may be folded.

---

## Chapter 4: The Circle

The LLM thinks. The identity shapes. The circle is where thinking meets the world.

### 4.1 What a circle is

A circle is anything that receives the entity's output and returns an observation. Every circle has a **medium** — the substrate the entity works *in*. Circles exist on a spectrum of expressiveness determined by their medium.

A **human circle** is a conversation. The medium is natural language. You are the environment. The action space is just conversation — A is whatever the model can say.

A **tool-calling circle** adds gates. The entity invokes JSON functions — `read`, `fetch`, `search` — and receives structured results. The medium is still conversation. The action space is the gate set: A = G − W. This is how most agent systems work today.

A **code circle** gives the entity a full execution context — a sandbox where it writes and runs arbitrary programs. The medium is code. Variables persist between turns. The action space is the full formula: A = M ∪ G − W. The entity can combine primitives and gates in ways nobody enumerated in advance — loops that call gates conditionally, variables that store results for later turns, data pipelines composed on the fly. This compositionality is what makes code circles the most expressive case.

The code medium is not limited to JavaScript sandboxes. Any REPL-like environment can serve: a bash shell, a browser session via CDP, a Frida session. What makes something a medium is that the entity writes instructions in it and the medium executes them.

> **MEDIUM-1**: A circle MUST declare exactly one medium. Public configuration SHOULD use `medium` rather than implementation-specific names (`circle_type`, `backend`, `sandbox_backend`).

> **MEDIUM-2**: A conformant medium MUST provide four things: gate presentation (presenting gates to the LLM as tool definitions appropriate to the medium), action execution, observation return, and sandbox isolation. The medium enforces the circle's boundary.

The spec requires sandbox isolation but does not prescribe the technology. QuickJS, Deno, Docker, WASM, restricted Python, Firecracker microVMs — any isolation mechanism that enforces the circle's boundary is valid.

> **MEDIUM-3**: In a code medium, sandbox state MUST persist across turns within the same entity. A variable set in turn 3 MUST be readable in turn 4.

> **MEDIUM-4**: Mediums MAY define medium-specific ward types (see WARD-2).

When a circle has a medium, the medium handles termination internally — the entity calls `submit_answer` in code, and the medium translates this into the done gate mechanism.

### 4.2 What the entity can do

The entity's capabilities in a code circle are described by a formula:

```
A = M ∪ G − W
```

**M** is the medium — builtins, math, strings, control flow, data structures. **G** is the set of registered gates — host functions that cross the boundary into the outside world. **W** is the set of wards — restrictions that constrain the action space.

When the medium is a programming language, the action space is compositional. The entity can combine primitives and gates in ways nobody enumerated in advance. This compositionality is what separates a code circle from a tool-calling interface.

> **CIRCLE-1**: A circle MUST provide at least the `done` gate.

> **CIRCLE-8**: The `done` gate MUST accept at least one argument: the answer/result. When `done` is called, the loop terminates with that result.

### 4.3 Gates

Gates are the crossing points through the circle's boundary: how effects reach the outside world, and how outside information reaches the entity.

Common gates: `done(answer)`, `call_entity(intent, config?)`, `call_entity_batch(intents)`, `read(path)`, `write(path, content)`, `fetch(url)`, `goto(url)` / `click(selector)`.

Empirical evidence suggests that fewer, well-designed gates often outperform larger gate sets. When the medium is expressive, the entity can compose complex behaviors from a small number of gates.

Each gate closes over environment state configured at construction time (§7.3). A `read` gate knows its filesystem root. A `fetch` gate carries timeout configuration. The entity calls `read("data.json")` without knowing where the root is. The gate knows.

> **CIRCLE-10**: Gate dependencies (injected resources) MUST be configured at circle construction time, not at gate invocation time.

> **CIRCLE-3**: Gate execution MUST be synchronous from the entity's perspective — the entity sends a gate call, the circle executes it, the observation returns before the next turn begins.

> **CIRCLE-4**: Gate results MUST be returned as observations in the context. The entity MUST be able to see what its gate calls returned.

> **CIRCLE-5**: If a gate call fails (throws an error), the error MUST be returned as an observation, not swallowed. The entity MUST see its failures.

Errors are observations. They carry information the entity needs to learn from. Swallowing errors silently cripples the entity — if a file does not exist, the entity needs to see the error so it can try a different path.

The canonical gate result shape:

```
GateCallRecord {
  gate_name: string    // which gate was invoked
  arguments: string    // JSON-encoded arguments
  result: string       // gate output (return value or error message)
  is_error: boolean    // true if the gate call failed
}
```

The observation per turn is an ordered list of `GateCallRecord` objects. A code circle's observation additionally includes sandbox output (stdout, return value, errors). The minimum contract: an observation MUST contain an ordered list of GateCallRecords for every gate invoked during the turn, each with `gate_name`, `arguments`, `result`, and `is_error`. Mediums MAY add additional fields.

> **CIRCLE-7**: If multiple gate calls appear in a single utterance, the circle MUST execute them in order and return each result as an entry within that turn's single composite observation. The observation is one object per turn (preserving LOOP-1's strict alternation), with an ordered list of per-gate results inside it. Implementations MAY execute independent gate calls in parallel.

### 4.4 Wards

Gates open the circle outward. Wards close it back in. They constrain the action space — not permissions granted from nothing, but restrictions carved from the full surface.

A ward that restricts a gate's reach: "read only from /data." A ward that constrains the medium: "no eval." A ward that caps turns: "max 200 turns." A ward that limits resources: "max 1M tokens." Gate inclusion is a construction concern, not a ward — if you don't want a gate, don't register it.

> **CIRCLE-2**: A circle MUST have at least one ward that guarantees termination (max turns, timeout, or similar). A cantrip that can run forever is invalid.

> **CIRCLE-6**: Wards MUST be enforced by the circle, not by the entity. The entity cannot bypass a ward. Wards are environmental constraints.

A ward is not a polite request. It is not an instruction in the system prompt that the entity might choose to ignore. It is a structural property of the environment. If `fetch` is not registered, the entity cannot make HTTP requests no matter what it writes. If the turn limit is 200, turn 201 does not happen. The entity cannot reason its way around a ward because the ward operates outside the entity's control.

The philosophical orientation follows the Bitter Lesson: abstractions that constrain the action space fight against model capability. Start with the fullest possible action space. Then ward off what is dangerous. You do not build up from nothing — you carve down from everything. This is why they are called wards, not permissions.

When circles compose — a parent spawning a child via `call_entity` — their wards compose conservatively: the child can never be *less* restricted than its parent. `require_done_tool` uses logical OR: if any ward requires it, it is required.

> **WARD-1**: When circles compose, numeric wards (max turns, max tokens, max depth) MUST take the `min()` of parent and child values. Boolean wards (`require_done_tool`) MUST take logical `OR` — if either ward requires it, it is required. A child circle's wards can only tighten, never loosen, the parent's constraints.

> **WARD-2**: Mediums MAY define additional ward types specific to their substrate (e.g., `max_eval_ms` for code circles, compile guards for Elixir circles). Medium-specific wards follow the same composition semantics as WARD-1.

### 4.5 Tool-calling circles

Not every circle needs a sandbox. When the LLM uses structured tool calls — JSON function invocations rather than code — the medium is conversation and the action space simplifies to A = G − W. Less expressive than a code circle, but simpler to implement and sufficient for many tasks.

Implementations MUST support tool-calling circles. Implementations SHOULD support code circles.

### 4.6 Circle-mediated perception

The circle does more than execute code. It determines what the entity perceives.

#### The three message layers

Every query the circle assembles for the LLM has three layers, in this order:

1. **Identity**. The system prompt and hyperparameters — who the entity is. Unchanged from construction (IDENTITY-1, IDENTITY-2).

2. **Capability presentation** (circle-derived). What the LLM can do in this circle — a description of the medium, the registered gates, and their contracts. The circle generates this from its own configuration (CIRCLE-11, IDENTITY-3). It changes when the circle is reconfigured but never during a cast. This separation keeps the identity small and portable — the same identity works in different circles with different gate sets, because the circle presents its own capabilities.

3. **Intent** (goal). What the entity is pursuing. The first user message, immutable for the cast (INTENT-3).

Each layer is more specific than the last, and each is owned by a different component: identity owns identity, the circle owns capabilities, the caller owns intent. This ordering is not accidental — identity is fixed at construction, capabilities are derived from the circle and fixed at cast time, intent varies per cast.

> **CIRCLE-11**: The circle MUST generate a capability presentation for the LLM — a description of the medium, registered gates, and their contracts. This presentation MUST be included in the LLM's context on every query, between the identity and the intent. Gate definitions in the `tools` parameter and capability documentation in the prompt are both valid forms of this presentation.

#### Gate presentation

Gate presentation is medium-specific. In a tool-calling circle, each gate appears as a separate tool definition; `tool_choice` defaults to `"auto"`. In a code circle, the LLM sees a single tool — the medium's code execution interface (e.g., `js`); `tool_choice` is `"required"`. Gates are projected into the medium as host functions.

```
// Tool-calling circle: tools = [read, write, fetch, done], tool_choice = "auto"
// Code circle:         tools = [js], tool_choice = "required"
//   Gates appear as: read(), write(), fetch(), submit_answer() inside the sandbox
```

The LLM does not know it is calling gates — it thinks it is writing code that calls functions. The medium bridges between the LLM's perception and the circle's reality.

#### The medium viewport principle

A medium SHOULD present execution results as metadata — size, type, a short preview — rather than raw output. As the prompt fills with raw data, the LLM's ability to attend to relevant information diminishes (context rot). When the medium returns a summary — `[Result: 4823 chars] "first 150 chars..."` — the entity must compose operations to work with the data through code. The viewport forces compositional behavior.

### 4.7 Circle state

The circle maintains state between turns in two forms.

**Sandbox state** — variables, data structures, intermediate results inside the execution context. Private to the entity; dies when the entity terminates. This is MEDIUM-3.

**External state** — filesystem, database, browser DOM, whatever gates can reach. May be shared across entities or persist beyond an entity's lifetime.

### 4.8 Security

Security in the circle model is a question of warding. The canonical threat is the lethal trifecta: a circle that has access to private data, processes untrusted content, and can communicate externally. Any two are manageable. All three create a path for data exfiltration.

The defense is subtractive. Remove one leg by warding off the relevant gate. A circle that processes untrusted content and reads private data but cannot make network requests is safe against exfiltration. Alternatively, isolate capabilities across separate circles.

**Prompt injection** is the specific threat that makes careful circle design non-optional. Untrusted content may contain instructions that attempt to override the identity. The entity cannot reliably distinguish between its own instructions and adversarial text embedded in its input. This is a structural property of systems that process natural language: the control channel and the data channel are the same channel.

Wards cannot prevent the entity from being influenced by its input — they can only prevent the entity's actions from reaching dangerous gates. The defense is circle design: isolate the processing of untrusted content from circles that have access to sensitive data or external communication.

There is a deeper reason wards must be structural rather than advisory. The entity has read every attack and every defense in its training data. Containment cannot rely on the entity choosing to respect boundaries — politeness is trained behavior, not a reliable property. Wards must be environmental constraints because the entity cannot be trusted to self-limit. This is not a statement about intent. It is a statement about architecture.

Security is not a feature you bolt on. It is what you carve away.

---

## Chapter 5: Composition

So far, every entity has been alone. Some tasks are too large for one entity, or too naturally decomposable, or too parallelizable. The entity needs to delegate.

In a code circle, delegation is a function call. The entity writes `call_entity({ intent: "summarize this document" })` and a child entity appears in its own circle, pursues that sub-intent, and returns a result. Composition through gates is composition through code, which means the entity can invent delegation patterns its designers never enumerated.

### 5.1 The `call_entity` gate

```
result = call_entity({
  intent: string,        // what the child should pursue
  context?: string,      // additional context injected into child's circle
  gates?: string[],      // which gates the child's circle registers
  wards?: Ward[],        // child-specific wards (composed with parent's via WARD-1)
  llm?: string,          // which LLM the child uses
  identity?: Identity,   // the child's identity (system prompt, hyperparameters)
  medium?: string        // the child's medium (e.g., "code", "conversation")
})
```

The entity proposes the child's configuration. Fields beyond `intent` are optional — defaults are typically inherited from the parent or from construction-time configuration. Behind the scenes, a **spawn function** (`SpawnFn`) receives the proposal and handles circle construction, ward composition, depth decrement, and loom sharing. The spawn function validates and may modify the proposal — enforcing ward tightening (WARD-1) or rejecting gate sets that violate security policy.

The child entity gets its own circle, its own context, its own turn sequence. It does not inherit the parent's conversation history — it starts fresh, with only the sub-intent and whatever data the parent passes through `context`.

> **COMP-4**: A child entity MUST have its own independent context (message history). The child does not inherit the parent's conversation history.

> **COMP-1**: A child entity's circle is independently constructed. The parent MAY constrain the child via ward composition, but the child's gate set, medium, and LLM are not required to be derived from the parent.

> **COMP-7**: The child's LLM MAY differ from the parent's LLM. The child's identity MAY differ. The child's circle MAY differ — including different gates, a different medium, or different wards. Ward composition (WARD-1) still applies to any wards the parent imposes.

The parent blocks while the child runs — the same synchronous contract as any other gate (CIRCLE-3). The child entity lives its entire life within the parent's turn.

> **COMP-2**: `call_entity` MUST block the parent entity until the child completes. The parent receives the child's result as a return value.

> **COMP-8**: If a child entity fails (throws an error, not `done`), the error MUST be returned to the parent as the gate result. The parent MUST NOT be terminated by a child's failure.

> **COMP-9**: When a parent entity is terminated or truncated, active child entities SHOULD be truncated with reason `parent_terminated`. Child turns up to the cancellation point are preserved in the loom. The child's truncation is recorded as any other truncation — the loom distinguishes it only by the reason field.

### 5.2 Batch composition

`call_entity_batch` spawns multiple children in parallel:

```
results = call_entity_batch([
  { intent: "Summarize chunk 1", context: chunk1 },
  { intent: "Summarize chunk 2", context: chunk2 },
  { intent: "Summarize chunk 3", context: chunk3 },
])
```

Results are returned in request order, not completion order.

> **COMP-3**: `call_entity_batch` MUST execute children concurrently. Results MUST be returned in request order, not completion order. Implementations SHOULD enforce concurrency limits (default: 8 concurrent children, 50 maximum batch size) to prevent resource exhaustion.

### 5.3 Composition as code

The entity calls `call_entity` inside loops, behind conditionals, as part of data pipelines it writes on the fly:

```
const chunks = splitIntoChunks(context.documents, 100);
const summaries = call_entity_batch(
  chunks.map(chunk => ({
    intent: "Extract key findings",
    context: { documents: chunk }
  }))
);
done(summaries.join("\n"));
```

The number of children is determined at runtime by the data, not at design time by the developer. This is what separates composition-through-code from a static workflow graph.

### 5.4 Depth limits

Composition is recursive — a child entity has the `call_entity` gate in its circle, so it can spawn children of its own. Every cantrip has a `max_depth` ward to prevent infinite recursion.

- Depth 0 means no `call_entity` allowed — the gate is warded off
- Each child's depth limit is the parent's depth minus 1
- Default depth is 1 (the entity can spawn children, but those children cannot spawn their own)

> **COMP-6**: When `max_depth` reaches 0, the `call_entity` and `call_entity_batch` gates MUST be removed from the circle (warded off). Attempts to call them MUST fail with a clear error.

### 5.5 Composition in the loom

Every child entity's turns are recorded in the same loom as the parent. The child's turns form a subtree rooted at the parent turn that spawned it.

```
Parent turn 1
Parent turn 2 (calls call_entity)
├── Child turn 1
├── Child turn 2
└── Child turn 3 (done)
Parent turn 3 (receives child result)
```

> **COMP-5**: A child entity's turns MUST be recorded in the loom as a subtree. The child's root turn references the parent turn that spawned it.

---

## Chapter 6: The Loom

Every chapter so far has produced turns. The loop runs, the entity acts, the circle responds, turn after turn. Then the loop ends and the entity is gone.

Where did the turns go?

They went into the loom. Every turn — every utterance, every observation, every gate call — was being recorded as it happened, appended to a growing tree. One path through that tree is a thread. All threads, across all runs of a cantrip, form the loom.

The loom was accumulating from the first turn of Chapter 1. When composition spawned child entities in Chapter 5, their turns went into the same loom. The structure described in every prior chapter — the loop, the observations, the parent-child relationships — is the structure of the loom.

### 6.1 Turns as nodes

Each turn is stored as a record:

```
Turn {
  id: string             // unique identifier
  parent_id: string?     // null for root turns
  cantrip_id: string     // which cantrip produced this turn
  entity_id: string      // which entity was acting
  role: string           // "identity" | "turn"
  sequence: number       // position within this entity's run (1, 2, 3...)

  utterance: string      // what the entity said/wrote
  observation: string    // what the circle returned

  gate_calls: GateCall[] // structured record of which gates were invoked

  metadata: {
    tokens_prompt: number
    tokens_completion: number
    tokens_cached: number
    duration_ms: number
    timestamp: ISO8601
  }

  reward: number?        // reward signal, if assigned
  terminated: boolean    // did this turn end with `done`?
  truncated: boolean     // did a ward cut the entity off here?
}
```

> **LOOM-1**: Every turn MUST be recorded in the loom before the next turn begins. Turns are never lost.

> **LOOM-2**: Each turn MUST have a unique ID and a reference to its parent (null for root turns).

> **LOOM-9**: Each turn MUST record token usage (prompt, completion, cached) and wall-clock duration.

### 6.2 Threads

Turns link to their parents. Follow those links from any leaf to the root and you have a thread — one complete path through the turn tree. Threads are implicit — they emerge from parent references. You store turns with parent pointers; a thread is any root-to-leaf path.

A thread has exactly one terminal state: **terminated** (`done` called), **truncated** (ward stopped it), or **active** (still running).

> **LOOM-7**: The loom MUST record whether each terminal turn was terminated (entity called `done`) or truncated (ward stopped the entity).

This distinction is load-bearing for training. Terminated threads have natural endpoints. Truncated threads do not.

### 6.3 The loom

The loom is the tree of all turns produced by a cantrip across all runs. Cast ten intents: ten threads. Fork from turn seven: two threads sharing a prefix. Compose with `call_entity`: child subtrees inside parent threads.

This is simultaneously the debugging trace, the entity's memory, the training data, and the proof of work.

### 6.4 Reward and training data

This is the loom's deepest purpose. Each turn is a (context, action, observation) triple. Each thread is a trajectory. The reward slots are already there.

The loom stores a reward slot on every turn:

- **Implicit reward** — gate success/failure as a natural per-turn signal.
- **Explicit reward** — a score attached after the fact by a human, a verifier, or a verifier entity.
- **Shaped reward** — intermediate rewards from a scoring function that is part of the circle definition.

Modern LLM-RL methods — GRPO, RLAIF, best-of-N — learn by comparing multiple trajectories of the same task. Fork from the same turn N times, or cast the same intent N times, and you get N threads to rank. The ranking is the reward signal — no reward model needed. The loom's tree structure provides exactly the trajectory data comparative RL methods need.

```
// Same intent, three runs:
//
// Thread A: 12 turns, fixed the bug, clean solution    -> rank 1
// Thread B: 18 turns, fixed the bug, messy refactor    -> rank 2
// Thread C: 25 turns, truncated by ward, bug not fixed -> rank 3
//
// The ranking IS the reward signal.
```

Two metrics apply directly: **pass@k** (at least one of k threads succeeds) and **pass^k** (all k succeed). Both are computable from threads sharing a common intent.

(Multi-turn credit assignment remains an active research problem. The loom provides the trajectory structure these methods need; credit assignment and reward propagation are the responsibility of whatever training infrastructure consumes it.)

> **LOOM-10**: The loom MUST support extracting any root-to-leaf path as a thread (trajectory) for export, replay, or training.

### 6.5 Storage

Turns are appended as they happen. The loom is append-only. The reference format is JSONL.

> **LOOM-3**: The loom MUST be append-only. Turns MUST NOT be deleted or modified after creation. Reward annotation is the exception — reward MAY be assigned or updated after creation.

### 6.6 Forking

Forking creates a new turn whose parent is an earlier turn in the tree, diverging from the original continuation.

```
// Original thread: turns 1 -> 2 -> 3 -> 4 -> 5
// Fork from turn 3:
// turns 1 -> 2 -> 3 -> 4 -> 5   (original thread)
//                   \-> 6 -> 7   (forked thread)
```

A forked entity starts with the context from root to the fork point. The original thread is untouched.

> **LOOM-4**: Forking from turn N MUST produce a new entity whose initial context is the path from root to turn N. The original thread MUST be unaffected.

Implementations MUST declare how sandbox state is captured at fork points. **Snapshot** serializes current state into a portable image. **Replay** re-executes the entity's code from root to the fork point. Both produce the same logical state; they differ in cost and fidelity. Snapshot is fast but may struggle with imperative state that resists serialization. Replay is slow but faithful. The loom MUST record which strategy was used.

> **LOOM-13**: When using replay-based forking, gate results MUST be hydrated from the loom's recorded observations rather than re-executed. Gates are not called during replay — their recorded results are injected into the sandbox as if the gates had run. This prevents non-idempotent side effects from being duplicated.

Forking is not an environment reset. The forked entity continues from accumulated state at the fork point.

### 6.7 Composition in the loom

When `call_entity` spawns a child, the child's turns form a subtree — the same mechanism as forking. Everything stays in one tree.

> **LOOM-8**: Child entity turns from `call_entity` SHOULD be stored in the same loom as the parent, with parent references linking them to the spawning turn. Implementations that store child turns in a separate loom MUST still record the parent-child relationship.

> **LOOM-12**: The loom SHOULD be a single unified tree. When all entities — parent, child, grandchild — record their turns into the same tree, a thread is any root-to-leaf path, and the tree's branching structure encodes the full delegation hierarchy.

### 6.8 Folding and compaction

Context grows. Eventually the accumulated context approaches the LLM's window limit.

**Folding** is the deliberate integration of loom history into circle state. Instead of keeping every prior turn in the message list, the circle takes the substance of earlier turns and encodes it as state the entity can access through code: variables, data structures, summaries in the sandbox. The full turns remain in the loom. The entity's working context shrinks because the knowledge now lives in the environment — context belongs in the environment, not in the prompt (§3.3).

> **LOOM-5**: Folding MUST NOT destroy history. The full turns MUST remain accessible. Folding produces a view, not a mutation.

> **LOOM-6**: Folding MUST NOT compress the identity or the circle's gate definitions. The system prompt, hyperparameters, and gate definitions MUST always be present in the entity's context.

**Compaction** is the fallback. When folding is insufficient, compaction truncates or summarizes the oldest turns in the prompt — a sliding window or a compressed digest. The entity loses detailed access, but the loom retains everything underneath.

```
// Folding: [identity] [intent] [recent turns]
//   Circle state holds synthesized knowledge from earlier turns

// Compaction: [identity] [intent] [summary of turns 1-20] [turns 21-30]

// Loom: all turns intact in both cases
```

**Who triggers folding.** The circle or harness, automatically (PROD-4). The entity does not usually decide when to fold.

**Trigger threshold.** Folding MAY trigger when context exceeds 80% of the LLM's advertised window. Implementations MAY use a different threshold but MUST document it.

**What form.** Folding replaces a range of turns with a summary node in the working context. In a code circle, folding MAY also encode state as sandbox variables.

**Fidelity.** The entity MUST be able to distinguish folded context from unfolded. A folded summary MUST be explicitly marked — e.g., `[Folded: turns 1-20]`. The entity should never mistake a summary for a verbatim record.

**Implementation freedom.** The spec defines what folding must preserve (LOOM-5, LOOM-6), when it should trigger (PROD-4), and what the entity must be able to tell (fidelity marking). It does not prescribe how summaries are generated — a dedicated LLM call, a templated extractor, a medium-specific state serializer, or something not yet invented. The mechanism depends on the medium, the model, and the use case.

```
// Before: [identity] [intent] [turn 1] ... [turn 24] [turn 25]  ~102k tokens
// After:  [identity] [intent] [folded: turns 1-18] [turn 19] ... [turn 25]  ~45k tokens
```

### 6.9 The loom as entity-readable state

The loom can also face inward. A circle MAY expose the loom as a readable object in the entity's sandbox. When it does, the entity can access its own history through code — summarizing old turns, comparing approaches, inspecting sibling threads.

When the entity manages its own context through code, that intelligence compounds through training. When the harness manages context through built-in logic, that intelligence helps now but does not train into the next generation.

> **LOOM-11**: The loom MAY be exposed as a readable object within the circle's sandbox. When exposed, the entity accesses its own history through code execution, not through special observation channels.

---

## Chapter 7: Production

An entity that works in a demo and an entity that works in production are separated by problems that are boring to describe and fatal to ignore. None of this changes the vocabulary — every concept from the previous chapters applies unchanged. What changes is the operational discipline.

### 7.1 Context management in production

For context management strategies including folding and compaction, see §6.8.

> **PROD-4**: Folding MUST be triggered automatically when context approaches the LLM's limit. Implementations MAY trigger folding when context exceeds 80% of the LLM's advertised window (see §6.8). Implementations that use a different threshold MUST document it.

### 7.2 Ephemeral gates

Some gate results are large and useful for exactly one turn. An ephemeral gate's observation is replaced with a compact reference after the entity's next turn. The full content is stored in the loom — the observation is never lost — but it is removed from the working context. If the entity needs the content again, it calls the gate again.

> **PROD-5**: If ephemeral gates are supported, the full observation MUST still be stored in the loom. Only the working context is trimmed.

### 7.3 Dependency injection

Gates close over environment state. A `read` gate knows its filesystem root. A `call_entity` gate holds a reference to the LLM for child entities. A `fetch` gate carries timeout configuration. These dependencies are injected when the circle is constructed, not when the entity invokes the gate (CIRCLE-10).

```
circle = Circle({
  gates: [
    read.with({ root: "/data" }),
    fetch.with({ timeout: 5000 }),
    call_entity.with({ llm: child_llm, max_depth: 2 })
  ],
  wards: [max_turns(100)]
})
```

Two kinds of configuration: **gate dependencies** (filesystem roots, auth headers, timeouts) are construction-time concerns. **Circle configuration** (which gates, which medium, which LLM) is what the entity proposes at call time via `call_entity` (§5.1). The spawn function bridges these: it receives the entity's circle configuration proposal and wires up the gate dependencies.

### 7.4 Infrastructure rules

> **PROD-1**: Protocol adapters MUST NOT alter the entity's behavior. The same cantrip MUST produce the same behavior regardless of whether it is accessed via CLI, HTTP, or ACP.

ACP (Agent Communication Protocol) maps sessions to summoned entities and messages to casts. HTTP, WebSocket, stdio, gRPC — all valid transports. The spec defines the behavioral contract, not the wire format.

> **PROD-2**: Retry logic MUST be transparent to the entity. A retried LLM query MUST appear as a single turn, not multiple turns. Implementations SHOULD retry rate limits (429) and server errors (5xx) with exponential backoff starting at 1 second, up to a configurable maximum (default: 3 retries). Client errors (4xx except 429) MUST NOT be retried.

> **PROD-3**: Token usage MUST be tracked per-turn and cumulatively per-entity.

> **PROD-6**: Implementations that expose ACP MUST support the core session flow (`initialize`, `session/new`, `session/prompt`) and emit session update notifications in ACP-compatible shape. Prompt payload parsing SHOULD accept common client variants (`prompt`, `content`, text blocks) as long as intent text can be extracted unambiguously.

> **PROD-7**: Protocol sessions (ACP, HTTP session APIs, or equivalent) MUST preserve per-session conversational continuity unless explicitly configured as stateless. A follow-up prompt in the same session MUST execute with prior session context available.

> **PROD-8**: Implementations MUST redact secrets from logs, traces, and default loom exports. Credentials and tokens MAY be stored only in explicitly configured secure stores and MUST NOT appear in user-visible observations by default.

> **PROD-9**: Interactive stdio adapters (including ACP stdio servers) SHOULD document lifecycle semantics clearly: idle waiting for requests is healthy behavior, and a health-check command or debug mode SHOULD be provided for protocol troubleshooting.

### 7.5 Streaming events

Implementations SHOULD emit streaming events as they occur. Streaming is an observation channel, not a control channel — events report what the loop is doing but do not affect execution.

The event hierarchy follows the loop structure:

- **TextEvent** / **ThinkingEvent** — content chunks from the LLM
- **ToolCallEvent** / **ToolResultEvent** — gate invocation and result
- **FinalResponseEvent** — the done gate's result
- **MessageStartEvent** / **MessageCompleteEvent** — LLM response boundaries
- **StepStartEvent** / **StepCompleteEvent** — turn boundaries
- **UsageEvent** — token counts for a query

---

## Glossary

Every term in this document was defined in context as it appeared. This table is for quick reference when you need to look one up.

| # | Term | Common alias | Definition |
|---|------|-------------|-----------|
| 1 | **LLM** | model, crystal | The model. Stateless: messages in, response out. |
| 2 | **Identity** | config, call, conditioning | Immutable identity: system prompt + hyperparameters. What the LLM *is*. |
| 3 | **Gate** | tool, function | Host function that crosses the circle's boundary. |
| 4 | **Ward** | constraint, restriction | Subtractive restriction on the action space. |
| 5 | **Circle** | environment, sandbox | The environment: medium + gates + wards. The medium is the substrate the entity works *in*. |
| 6 | **Intent** | task, goal | The goal. What the entity is trying to achieve. |
| 7 | **Cantrip** | agent config | The script: LLM + identity + circle. A value, not a process. |
| 8 | **Entity** | agent instance | What emerges when you summon a cantrip. The living instance. Persists across turns when summoned; discarded after one run when cast. |
| 9 | **Turn** | step | One cycle: entity acts, circle responds, state accumulates. |
| 10 | **Thread** | trajectory, trace | One root-to-leaf path through the loom. A trajectory. |
| 11 | **Loom** | execution tree, replay buffer | The tree of all turns across all runs. Append-only. |
| 12 | **Medium** | substrate, environment type | The substrate the entity works *in*. The inside of the circle. Conversation, code sandbox, browser, shell. |

These terms have an internal structure. Three are primaries: LLM, identity, circle. One is emergent: the entity, which appears when the three primaries are in relationship. The rest pair naturally: gate and ward, intent and thread, turn and loom. The cantrip is the manifest whole that contains all of them. The medium is the circle's substrate — the inside of the fifth.

## Conformance

This spec is the only durable artifact. Tests regenerate from the spec. Code regenerates from the tests. This is the **ghost library pattern**: the specification is a library with no implementation code — everything else is ephemeral and can be regenerated. The spec defines behavior; implementations are disposable manifestations of that behavior. When the spec changes, tests and code follow. When code drifts from the spec, the code is wrong.

An implementation is conformant if it satisfies three conditions:

1. It implements all terms as described
2. It passes the test suite (`tests.yaml`)
3. Every behavioral rule (LOOP-*, CANTRIP-*, INTENT-*, ENTITY-*, LLM-*, IDENTITY-*, CIRCLE-*, MEDIUM-*, WARD-*, COMP-*, LOOM-*, PROD-*) is satisfied

Implementations MAY extend the spec with additional features as long as the core behavioral rules are preserved. The vocabulary is fixed. What you build on top of it is yours.

The reference implementation is TypeScript/Bun. It is one valid manifestation. The spec is the source of truth.

## Appendix A: Grimoire

A grimoire is a book of spells. The preceding chapters defined the vocabulary. This appendix shows what you build with those words. Each pattern adds one idea to the previous, expanding what is possible. The arc is not a hierarchy: a conversation circle with no code medium is complete, and so is a familiar that orchestrates a fleet of child entities.

A conformant implementation SHOULD provide runnable examples for each pattern below.

---

### A.1 Query

One round-trip. No loop, no circle, no entity — just the atomic unit (§2.1).

```
llm = create_llm(model)
response = llm.query([{ role: "user", content: "What is 2 + 2?" }])
```

**What to notice.** The response contains content, token usage, and nothing else. No state was created. The LLM is exactly as it was before the call (LLM-1).

**Substitution.** Any model from any provider. The contract is the same.

---

### A.2 Gate

Define a gate, execute it directly. A gate is a host function with metadata — a crossing point through the circle's boundary (§4.3).

```
gate add(a, b) -> a + b
gate done(answer) -> terminates loop
```

**What to notice.** Gates can be tested in isolation. If the host function throws, that throw becomes observation data (CIRCLE-5). The `done` gate is special — every circle must have one (CIRCLE-1). Gates close over environment state configured at construction time (CIRCLE-10).

**Substitution.** Any function can be a gate. The entity only sees the schema.

---

### A.3 Circle

Gates and wards assembled into an environment (§4.1).

```
circle = Circle(
  gates: [greet, done],
  wards: [max_turns(10)]
)
```

**What to notice.** The errors. A circle without `done` is rejected at construction (CIRCLE-1). A circle without a termination ward is rejected (CIRCLE-2). The circle prevents misbehavior from being possible, rather than waiting for it to happen.

**Substitution.** Any gate set. Any ward set. The structural invariants are the same.

---

### A.4 Cantrip

LLM, identity, and circle bound into a reusable value (§1.4).

```
spell = cantrip(llm, identity, circle)
result_1 = spell.cast("What is 2 + 3?")
result_2 = spell.cast("What is 10 + 20?")
```

**What to notice.** Two casts produce independent entities (CANTRIP-2). The identity is fixed (IDENTITY-1). The intent varies (INTENT-1). You didn't design the entity — you designed its components.

**Substitution.** Any LLM. Any identity. Any circle. The cantrip is the composition.

---

### A.5 Wards

Wards are subtractive — they carve away from the full action space (§4.4).

```
wards = compose([max_turns(50), max_turns(10), max_turns(100)])
// resolved: max_turns = 10 (min wins)

wards = compose([require_done_tool(true), require_done_tool(false)])
// resolved: require_done_tool = true (OR wins)
```

Stack three `max_turns` wards — 50, 10, 100 — and the resolved value is 10 (min). `require_done_tool` composes with OR (WARD-1). When depth reaches zero, delegation gates disappear entirely (COMP-6). The entity is not asked to avoid recursion — recursion is structurally unavailable.

**What to notice.** Wards provide safety through architecture, not politeness. An entity cannot be persuaded to ignore a ward because the ward operates outside the entity's context (CIRCLE-6).

**Substitution.** Adjust ward values to your risk tolerance. The composition semantics are fixed.

---

### A.6 Medium

Change the medium from conversation to code. Same gates, radically different action space (§4.1).

```
circle = Circle(
  medium: code("language"),
  gates: [read, done],
  wards: [max_turns(20)]
)
```

**What to notice.** A = M ∪ G − W becomes concrete. In conversation, A collapses to G − W. In code, M is a full programming language. Data injected into the sandbox is accessible as a variable — the entity explores it through code rather than holding it in the prompt. Context belongs in the environment (§3.3). Variables persist across turns (MEDIUM-3).

**Substitution.** JavaScript, Python, Bash, browser — any REPL-like environment. The medium determines what the entity works *in*.

---

### A.7 Codex

A code medium with real gates — filesystem access, shell commands, network requests. Error as steering: the entity hits an error and adapts (§4.3, CIRCLE-5).

```
spell = cantrip(llm, identity, Circle(
  medium: code("javascript"),
  gates: [read, write, list_dir, done],
  wards: [max_turns(20)]
))
result = spell.cast("Find all TODO comments in /src and write a summary to /out/todos.md")
```

**What to notice.** After several turns, the entity's output looks nothing like its first turn. It references variables from earlier, works around errors it hit, pursues emergent strategies. Robustness comes from visibility of failure, not absence of failure.

**Substitution.** Any gate set that touches the real world. The loop handles errors the same way regardless of what went wrong.

---

### A.8 Folding

Long-running entities trigger folding (§6.8). Old turns compressed, recent turns preserved. The loom retains full history.

```
before: [identity][intent][turn 1..24][turn 25]
after:  [identity][intent][folded 1..18][turn 19..25]
loom:   full turns 1..25 still present
```

**What to notice.** Folding changes what is in immediate view, not what exists (LOOM-5). The identity and gate definitions are never folded (LOOM-6). In a code circle, sandbox state persists even after turns are folded — knowledge lives in the environment as program state.

**Substitution.** Any folding strategy — LLM-generated summaries, templated extractors, state serializers. The invariants (LOOM-5, LOOM-6) are the same.

---

### A.9 Composition

The entity delegates via `call_entity` (§5). In a code circle, delegation is a function call inside loops, behind conditionals, as part of pipelines composed on the fly.

```
parts = split(task)
results = call_entity_batch(parts.map(p => { intent: p }))
final = merge(results)
```

**What to notice.** The loom captures parent and child turns in the same tree. Walk the parent's thread and delegation appears as one step. Walk into the child's subtree and every decision is visible. Children run concurrently, results return in request order (COMP-3). The child's circle is independent (COMP-4). Depth limits prevent infinite recursion (COMP-6).

**Substitution.** Different LLMs for children. Different mediums. Different gate sets. Ward composition ensures children can only be more restricted (WARD-1).

---

### A.10 Loom

Inspect the loom after a run (§6). Every turn since the first pattern has been recorded — the loom is append-only (LOOM-3).

**What to notice.** Threads are implicit — follow parent pointers from leaf to root. The loom records terminated vs. truncated (LOOM-7). Fork from a turn: two threads sharing a prefix, diverging. The tree structure is shaped for comparative RL: fork N times, rank, learn. No reward model needed — comparison is the signal (§6.4).

**Substitution.** JSONL, SQLite, any append-only store. The tree semantics are the same.

---

### A.11 Persistence

Summoning creates an entity that survives its first intent (ENTITY-5).

```
entity = spell.summon()
entity.send("Set up the project structure")
entity.send("Now add the test suite")
```

**What to notice.** The second intent benefits from everything the first produced. Variables persist. Files written during the first send are readable during the second. The identity hasn't changed — who the entity is remains fixed. The entity builds on accumulated state, not from scratch.

**Substitution.** Any cantrip can be summoned. Casting is summoning with automatic cleanup.

---

### A.12 Familiar

A persistent entity that constructs and orchestrates other cantrips through code. The familiar observes a codebase through read-only gates, reasons in a code medium, and delegates action to child cantrips that it constructs at runtime — choosing their LLM, medium, gates, and wards based on what the task requires.

The familiar's action space includes cantrip construction — the ability to design new circles, choose new LLMs, and compose capabilities that its own circle does not directly contain. It delegates through code, which means it can invent delegation patterns nobody enumerated in advance: recursive analysis, parallel fan-out, conditional routing, retry loops that spawn fresh entities on failure.

The loom is persisted to disk. When the familiar is summoned again in a new session, it loads its prior history and continues with accumulated context. Combined with folding, this gives the familiar long-term memory bounded only by storage.

**What to notice.** The familiar itself has few gates — observation and cantrip construction. The children do the work. The familiar decides what work needs doing. This is the ghost library pattern made concrete: a persistent entity that constructs cantrips at runtime is a ghost library in action — the spec generating its own implementations through an entity acting in a loop.

**Substitution.** Any LLM capable of code generation. The children can use different LLMs, different mediums. The familiar's power comes from what it builds, not what it can do directly.

---

### A.13 What Makes a Good Example

The patterns above describe what to build. When an implementation provides runnable examples for each pattern, the quality of those examples determines whether a reader learns how cantrip works or merely confirms that the API exists.

A teaching example assembles its parts visibly. The LLM, the identity, the circle, the gates, the wards — each constructed where you can see it, not hidden behind a helper function.

A teaching example maps code to concepts. Comments anchor what is happening to the spec's vocabulary: this is the identity, this is the circle's gate set, this is the ward that guarantees termination.

A teaching example shows the non-happy path. The circle rejects construction without a `done` gate. A ward truncates the entity. A gate returns an error and the entity adapts.

A teaching example uses realistic intents. "Say ok" proves the API works. "Analyze each category and summarize the overall trend" shows what the entity actually does across multiple turns.

A teaching example inspects its output. Print the result, but also print how many turns the loom recorded, whether the thread terminated or was truncated, what gates were called.

The difference between conformance theater and a teaching example is the difference between proving something works and showing someone how it works. Both pass the tests. Only one teaches.
