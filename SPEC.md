# Cantrip

>"The cantrips have been spoken. The patterns of force are aligned. Now it is up to your machine."
>
> — Gargoyles: Reawakening (1995)

**Version**: 0.1.0-draft
**Status**: Draft — behavioral rules for implementation

## Introduction

A cantrip is a spell. In fantasy games, it refers to the simple starter spells that come in your spellbook at level 1. The etymology is thought to be related to Gaelic "Canntaireachd", a piper's mnemonic chant. It's a loop of language.

This document is a starter spellbook of your own. It describes a method for creating spells using the tools of modern summoning: a language model, a computer, and a prompt. It's language loops all the way down.

A language model takes text in and gives text back. You send it a prompt, it returns a completion. One pass — no memory, no consequences, no relationship between what it says and what happens next. This is the most simple way to interact with these systems: you input text, get text out. A "base model" is just this, autocomplete, token by token.

To make it do things, you close the loop. You take the model's output, run it as code in some kind of environment, and then let it observe the effects and act accordingly. This can be as simple as a chat interface: the model sends text to your mind, where it's interpreted by whatever it is in human minds that interprets language. Then you respond in language, and the model interprets it, and so on.

You can attach another language model to the loop, creating a "backrooms": the two models interpret each other's language and affect each other's internal state. But the chatbot and the backrooms don't have ontological hardness: their internal realities are pliable, dreamlike, they don't have persistent states or predictable behavior. 

Attach a verifiable environment – a shell, a REPL, a browser, a prover, a game — and feed the result back as input. Now it can act, observe, and act again. Now what it writes has consequences it can predict and adjust for. The environment pushes back: code runs or crashes, files exist or don't, tests pass or fail. The model sees that pushback and adjusts. Turn by turn, it accumulates experience. It gets smarter about the task. It starts doing things its designers never specifically enumerated, because the action space is a programming language and programming languages are compositional.

That's the shape of this document: call and response. You draw a circle, you speak into it, something answers. The answer changes what you say next. Each turn through the loop brings the model closer to the task or reveals why the task is harder than it looked. The repetition is the mechanism. The loop continues until the work is done or a limit is reached.

This spellbook gives names to the parts of that loop. There are eleven terms. Three are fundamental: the **crystal** (the model), the **call** (the invocation that shapes it), and the **circle** (the environment it acts in). Everything else is what happens when you put those three together and let the loop run.

Why new names? The existing ones — "agent," "tool," "environment" — are overloaded. They carry assumptions from specific frameworks and mean different things to different people. These eleven terms are precise within this system: each one maps to exactly one concept, and the concepts compose cleanly from a chat interface all the way up to a multi-agent system where parent entities delegate to children. A chat window where you talk to a model is a cantrip with a human circle. A tool-calling agent that invokes JSON functions is a cantrip whose action space is just its gates. A code circle — where the entity writes and runs arbitrary programs in a sandbox — is the most expressive case, the largest action space, and the one this document spends the most time with. What the entity acts *in* — the conversation, the sandbox, the browser — is the **medium**. Every circle has exactly one.

The same pattern works at every scale. The simplest cantrip is a crystal in a loop with one gate (`done`) and no wards beyond a turn limit — a model that can try things and say when it's finished. The most complex is a tree of entities with recursive composition, a loom feeding comparative reinforcement learning, and circles nested inside circles. Both are described by the same eleven terms. You don't rename them — you configure them differently. You add components — more gates, more wards, richer circles — but never a twelfth concept.

One more thing about what this document is and isn't. It describes behavior, not technology. It says "the circle must provide sandboxed code execution" — not "use QuickJS." It says "the crystal takes messages and returns a response" — not "use the Anthropic SDK." Any implementation that passes the accompanying test suite (`tests.yaml`) is a valid cantrip. Terms are defined in context as they appear; the Glossary at the end is there for quick reference.

---

## Chapter 1: The Loop

Everything in this document — every term, every rule, every architectural decision — exists to give structure to one idea: a model acting in a loop with an environment. The loop is the foundation. Start here.

### 1.1 The turn

Each cycle through the loop is called a **turn**. A turn has two halves.

First, the **entity** — the running instance of the model inside the loop — produces an **utterance**: text that may contain executable code or structured calls to the environment. Then the **circle** — the environment — executes what the entity wrote and produces an **observation**: a single composite object containing an ordered list of results, one entry per gate call, plus sandbox output if applicable. The observation feeds into the next turn as one unit. State accumulates.

> **LOOP-1**: The loop MUST alternate between entity utterances and circle observations. Two consecutive entity utterances without an intervening observation MUST NOT occur.

This strict alternation is what makes the loop a loop and not a monologue. The entity acts, the world responds, the entity acts again with the world's response in hand. Each turn is a learning moment — the entity sees what its code actually did, not what it hoped it would do.

Two more terms before we move on. The recipe that defines the loop — which model to use, how to configure it, what environment to place it in — is called a **cantrip**. The goal the entity is pursuing is called an **intent**. Both get their own full treatment later. For now, what matters is the cycle: act, observe, repeat.

### 1.2 What the entity perceives

On every turn, the entity needs to know two things: what it's supposed to do, and what has happened so far.

The **call** — the immutable configuration that shapes the model's behavior — and the **intent** — the goal — are always present. Think of them as the entity's fixed orientation: who it is, and what it's after. Those never change.

Everything beyond that is mediated by the circle. The circle determines what the entity perceives each turn. In the simplest design, the circle presents the full history of prior turns as a growing message list — every utterance, every observation, appended in order. This is how most agent systems work today. It is one valid approach, and the most expensive one. In a code circle, the entity can access state through code instead: reading variables, querying data structures, inspecting files that persist between turns. Both are valid circle designs. What the entity sees is the circle's decision.

> **LOOP-5**: The entity MUST receive the call and the intent on every turn. How prior turns are presented — as a message history, as program state, or as a combination — is determined by the circle's design. The circle mediates what the entity perceives.

This rule is deliberately permissive. A circle that stuffs every prior turn into the prompt is conformant. A circle that stores prior turns as program state the entity accesses through code is also conformant. The call and intent are the only things the spec requires on every turn. Everything else is a design choice, and the circle makes it.

### 1.3 Termination and truncation

Every loop ends. The question is how, and the answer matters more than you might expect.

**Terminated** means the entity called the `done` gate — a special exit point in the environment that signals "I believe the task is complete." The entity chose to stop. It had the opportunity to finish its work and took it.

**Truncated** means a **ward** cut the entity off. A ward is a restriction on the loop — a maximum number of turns, a timeout, a resource limit. The environment chose to stop. The entity was interrupted, not finished. It might have had more to do.

> **LOOP-2**: The loop MUST terminate. Every cantrip MUST have at least one termination condition (a `done` gate, or text-only response when `require_done` is false) AND at least one truncation condition (a max turns ward).

Both conditions are required because they serve different purposes. The `done` gate is how the entity signals success. The max turns ward is the safety net that prevents infinite loops. A cantrip that can run forever is invalid. A cantrip with no way to signal completion is useless.

> **LOOP-3**: When the `done` gate is called, the loop MUST stop after processing that gate. Any remaining gate calls in the same utterance MAY be skipped.

> **LOOP-4**: When a ward triggers truncation, the loop MUST stop. The implementation SHOULD generate a summary of what was accomplished before the entity was cut off.

There is a third case worth mentioning. Sometimes the entity produces a text-only response — no code, no gate calls, just words. The loop needs a policy for this. The cantrip's `require_done` flag controls the answer. When `require_done` is false (the default), a text-only response is a natural stopping point: the entity said what it had to say and made no further moves. When `require_done` is true, only an explicit `done` gate call terminates the loop — text-only responses are treated as turns that happen not to use gates, and the loop continues.

> **LOOP-6**: If `require_done` is false (default) and the entity produces a text-only response (no gate calls), the loop MUST treat that as implicit termination. If `require_done` is true, a text-only response MUST NOT terminate the loop — only a `done` gate call terminates.

Why does the terminated/truncated distinction matter? Because it travels with the data. A terminated thread is a completed episode — training data with a natural endpoint. A truncated thread is an interrupted episode — the entity's final state shouldn't be treated as a conclusion because it wasn't one. Implementations MUST record which occurred.

### 1.4 The cantrip, the intent, and the entity

Three terms have been floating through this chapter. Now they get pinned down.

A **cantrip** is the recipe that produces the loop. It binds a crystal to a circle through a call — which model, which configuration, which environment. A cantrip is a value, not a running process. You write it once and cast it many times.

> **CANTRIP-1**: A cantrip MUST contain a crystal, a call, and a circle. Missing any of these is invalid.

> **CANTRIP-2**: A cantrip is a value. It MUST be reusable — casting it multiple times on different intents MUST produce independent entities.

> **CANTRIP-3**: Constructing a cantrip MUST validate that the circle has a `done` gate (CIRCLE-1) and at least one truncation ward (CIRCLE-2).

An **intent** is the reason the loop runs — the goal, the task, the thing the entity is trying to achieve. Same cantrip, different intent, different episode. The intent is what varies between runs.

> **INTENT-1**: The intent MUST be provided when casting a cantrip. A cantrip cannot be cast without an intent.

> **INTENT-2**: The intent MUST appear as the first user message in the entity's context, after the system prompt (if any).

> **INTENT-3**: The intent is immutable for the lifetime of a cast. The entity cannot change its own intent mid-episode. An invoked entity may receive new intents as subsequent casts (ENTITY-5).

And the **entity** is what appears when you cast a cantrip on an intent and the loop starts running. This is the one that's hard to pin down, because you don't build it — it arises.

Watch what happens after a few turns.

The crystal's output on turn twelve doesn't look like its output on turn one. It's referencing variables it created on turn four. It's working around an error it hit on turn seven. It's pursuing a strategy that emerged from something it noticed on turn nine — a pattern in the data that nobody told it to look for. The call didn't ask for this strategy. The circle didn't suggest it. It appeared in the space between them, born from the accumulation of action and observation.

This is the entity. Not a thing you built — a thing that arose. The crystal is the same crystal it was before the loop started. The call hasn't changed. The circle is just an environment, doing what environments do. But the process running through all three of them has developed something that looks uncomfortably like perspective. It has context. It has momentum. It has preferences shaped by what it's tried and what worked.

You didn't design the entity. You designed the crystal, the call, and the circle. The entity is what happened when you put them together and let the loop run.

It will exist for as long as the loop runs. When the loop stops — task complete, budget exhausted, ward triggered — the entity is gone. The crystal remains, unchanged. The circle can be wiped or preserved. But the entity, that particular accumulation of context and strategy and in-context learning, is over. It lived in the loop and the loop is done.

Unless you recorded it. But that's a later chapter.

> **ENTITY-1**: An entity MUST be produced by casting a cantrip on an intent. There is no other way to create an entity.

> **ENTITY-2**: Each entity MUST have a unique ID. Implementations MUST auto-generate a unique entity ID if one is not provided by the caller.

> **ENTITY-3**: An entity's state MUST grow monotonically within a thread (modulo folding, which is a view transformation, not deletion — see Chapter 6).

> **ENTITY-4**: When an entity terminates or is truncated, its thread persists in the loom. The entity ceases but its record endures.

Invoking a cantrip produces a persistent entity. The initial intent starts the loop. When the loop completes — done or truncated — the entity persists. You can provide another intent as a new cast, and the loop resumes with accumulated state. The entity remembers what it did. A chat session is an invoked entity. A REPL session is an invoked entity.

Casting is a convenience: invoke, run one intent, return the result, discard the entity. Most of the examples in this document describe casting, because most tasks are one-shot. But the underlying mechanism is always invocation — casting is just invocation with automatic cleanup.

> **ENTITY-5**: An invoked entity persists after its loop completes. It MAY receive additional intents as new casts. State accumulates across all casts.

> **ENTITY-6**: Invoking a cantrip multiple times MUST produce independent entities, just as casting does (CANTRIP-2).

The crystal, the call, and the circle each have their own chapters. The entity does not, because the entity is not a component you configure. It is what emerges from the components you did configure, once the loop begins.

### 1.5 The four temporal levels

Four verbs describe what happens in this system, and they operate at four distinct timescales. Getting them straight prevents a category of confusion that plagues agent frameworks — conflating a single API call with a full task lifecycle.

**Query** is the atomic unit. One round-trip to the crystal: messages in, response out. The crystal is stateless, so each query is independent. The crystal has no memory of prior queries — the caller reconstructs context by assembling messages before each query. In code: `crystal.query(messages, tools)`.

**Turn** is one cycle of the loop. The entity produces an utterance (which may trigger one or more queries to the crystal). The circle executes what the entity wrote and returns an observation. State accumulates. A turn is the atom of experience — the smallest unit that has both action and consequence.

**Cast** is one complete episode. A cantrip is cast on an intent, the loop runs turn by turn until `done` is called or a ward triggers, and a result comes back. Casting is the one-shot pattern: invoke, run one intent, return, discard. Most examples in this document describe casting. In code: `cantrip.cast(intent)`.

**Invoke** creates a persistent entity. The entity survives the completion of its first intent. You can send it additional intents, and the loop resumes with accumulated state. A chat session is an invoked entity. A REPL session is an invoked entity. Casting is invoke with automatic cleanup. In code: `cantrip.invoke()` returns an entity; `entity.cast(intent)` runs one intent through it.

These nest cleanly: an invocation contains one or more casts, a cast contains one or more turns, a turn contains one or more queries. The nesting is strict — a query never spans turns, a turn never spans casts. The vocabulary in this document uses all four consistently.

### 1.6 The RL correspondence

If you know reinforcement learning, this table shows how the vocabulary maps. If you don't, skip ahead — the spec teaches everything you need without it.

The mapping is structural, not formal. Cantrip's terms parallel RL concepts in their relationships — the crystal is to cantrip what the policy is to RL, the circle is what the environment is to RL. These aren't mathematical equivalences you can plug into RL equations. They're structural parallels that help you reason about the system if you already have RL intuitions.

| RL concept | Cantrip equivalent | Notes |
|-----------|-------------------|-------|
| Policy | Crystal + Call | Frozen weights conditioned by immutable identity (prompt + hyperparameters) |
| Goal specification | Intent | The desire that shapes which actions are good |
| State s | Circle state | Accessed through gates. The message list is one circle design, not the default |
| Action a | Code the entity writes | A = (M + G) minus W |
| Observation o | Gate return values + sandbox output | Rich, unstructured |
| Reward r | Implicit or explicit | Implicit: gate success/failure. Explicit: verifier scores. Comparative: ranking threads of the same intent |
| Terminated | `done` gate called | Entity chose to stop |
| Truncated | Ward triggered | Environment chose to stop |
| Trajectory | Thread | One root-to-leaf path through the loom |
| Episode | Cast | One cast: intent in, result out. An invoked entity may span multiple casts (episodes). |
| Replay buffer | Loom | Richer: the tree structure provides the trajectory data comparative RL methods need |
| Environment reset | New entity, clean circle | Forking is NOT a reset — it continues from prior state |

The loom's relationship to modern RL methods is developed fully in Chapter 6.

### 1.7 A complete example

All the pieces in one place. Here's a cantrip lifecycle, end to end — a file-processing task: count the words in every `.txt` file in a directory and report the total.

**The cantrip.** Crystal: any model that supports tool calling. Call: a system prompt ("You are a file-processing assistant. Use code to solve tasks efficiently.") and default hyperparameters. Circle: a code medium with three gates — `read(path) -> string`, `list_dir(path) -> string[]`, and `done(answer)` — a ward of max 10 turns, and `require_done: true`. The circle's filesystem root is `/data`.

**The intent.** "Count the total number of words across all .txt files in /data and return the count."

**Turn 1.** The cantrip is cast. The entity appears, receives the call and intent. It produces an utterance:
```
const files = list_dir("/data");
```
The circle executes the gate call. Observation: `GateCallRecord { tool_call_id: "tc_1", gate: "list_dir", ok: true, result: ["a.txt", "b.txt", "c.txt"] }`.

**Turn 2.** The entity sees three files. It reads all of them:
```
const a = read("/data/a.txt");
const b = read("/data/b.txt");
const c = read("/data/c.txt");
```
Observation: three `GateCallRecord` objects, each with `ok: true` and the file contents in `result`. The sandbox now holds variables `files`, `a`, `b`, `c`.

**Turn 3.** The entity counts words and terminates:
```
const total = [a, b, c]
  .map(text => text.split(/\s+/).filter(w => w.length > 0).length)
  .reduce((sum, n) => sum + n, 0);
done(total);
```
Observation: `GateCallRecord { tool_call_id: "tc_7", gate: "done", ok: true, result: 1547 }`. The loop terminates.

**The loom.** Three turns, one thread. Turn 1: `parent_id: null`, `terminated: false`. Turn 2: `parent_id: turn_1`, `terminated: false`. Turn 3: `parent_id: turn_2`, `terminated: true`. Each turn records token usage, duration, utterance, and observation. The thread is a complete, terminated episode — usable as training data, a debugging trace, or a template for forking.

That's the whole vocabulary applied to a simple task: a crystal in a circle, shaped by a call, pursuing an intent, producing turns recorded in a loom. The entity appeared at turn 1 and vanished at turn 3. The thread persists.

---

## Chapter 2: The Crystal

The crystal is the model. You send it messages, it sends back a response. That is the entire interface — and the simplicity is the point.

A crystal does not act on its own. It has no memory between queries, no persistent state, no ongoing relationship with the world. You send it a list of messages — system instructions, prior conversation, whatever context you've assembled — and it sends back text, or structured calls to gates, or both. Then it's done. The next time you query it, you must send everything again. The crystal does not remember that there was a last time.

> **CRYSTAL-1**: A crystal MUST be stateless. Given the same messages and tool definitions, it SHOULD produce similar output (modulo sampling). It MUST NOT maintain internal state between queries.

This statelessness is not a limitation of current technology. It is the contract. The crystal is a function: messages in, response out. Everything that makes an entity seem to learn and adapt across turns — everything described in Chapter 1 — comes from the loop feeding the crystal's own prior output back as input. The crystal itself is the same on every query. The context around it changes. The learning lives in the loop, not in the crystal.

### 2.1 The crystal contract

What makes something a crystal? It satisfies this contract:

```
crystal.query(messages: Message[], tools?: ToolDefinition[], tool_choice?: ToolChoice) -> Response
```

The inputs:
- `messages` — an ordered list of messages (system, user, assistant, tool). The crystal sees the full conversation as the caller has assembled it.
- `tools` — an optional list of gate definitions, expressed as JSON Schema. These describe what the crystal can ask the environment to do.
- `tool_choice` — controls whether the crystal must use gates ("required"), may use them ("auto"), or must not ("none").

The response contains:
- `content` — text output (may be null if the crystal only made gate calls)
- `tool_calls` — an optional list of gate invocations, each with an ID, gate name, and JSON arguments
- `usage` — token counts (prompt, completion, cached)
- `thinking` — optional reasoning trace (for models that support extended thinking)

Every response must include at least one of the first two fields. A response with neither text nor gate calls is not a response — the crystal produced nothing.

> **CRYSTAL-2**: A crystal MUST accept messages up to its provider's context limit. When input exceeds that limit, the crystal MUST return a structured error (not silently truncate). The caller — circle or harness — is responsible for staying within limits via folding (§6.8).

> **CRYSTAL-3**: A crystal MUST return at least one of `content` or `tool_calls`. A response with neither is invalid.

> **CRYSTAL-4**: Each `tool_call` MUST include a unique ID, the gate name, and arguments as a JSON string.

The unique ID matters because gate results must be matched back to the calls that produced them. Without it, the crystal cannot distinguish which observation came from which request.

> **CRYSTAL-5**: If `tool_choice` is "required", the crystal MUST return at least one tool call. If the provider doesn't support forcing tool use, the implementation MUST simulate it (e.g., by re-prompting).

### 2.2 The swap

Here's a thought experiment that reveals what the crystal really is. Take a working cantrip — a system prompt, an environment with gates and wards, an intent — and replace the crystal. Keep everything else the same. The circle doesn't change, the call doesn't change, the gates and wards and intent are identical.

But the entity that appears behaves differently. It reasons differently, makes different mistakes, pursues different strategies, writes different code.

The crystal is the one component you swap to change how the entity thinks without changing what it can do or where it acts. Everything else — the environment, the conditioning, the available actions — stays fixed. Only the intelligence varies. This is what it means for the crystal to be a separable component of the loop, and it's the reason the spec treats it as one.

### 2.3 Provider implementations

In practice, crystals come from different providers, each with their own API, authentication, and way of representing messages and tool calls. The spec requires support for at least these families:

- **Anthropic** (Claude models)
- **OpenAI** (GPT models)
- **Google** (Gemini models)
- **OpenRouter** (proxy to many providers)
- **Local** (Ollama, vLLM, any OpenAI-compatible endpoint)

The provider implementation translates between the crystal contract above and the provider's native format. From the loop's perspective, every crystal looks the same.

> **CRYSTAL-6**: Provider implementations MUST normalize responses to the common crystal contract. Provider-specific fields (stop_reason, model ID, etc.) MAY be preserved as metadata but MUST NOT be required by consumers.

This normalization is what makes the swap possible. If consumers depended on provider-specific fields, changing the crystal would break the loop. The contract is the boundary. Everything behind it is the provider's business.

---

## Chapter 3: The Call

The crystal is a function. The call is what you pass to it — or more precisely, the part that stays the same every time you pass it. The call is everything that shapes the crystal's behavior before any intent arrives. It's small, it's fixed, and it doesn't change for the lifetime of the cantrip.

> **CALL-1**: The call MUST be set at cantrip construction time and MUST NOT change afterward.

### 3.1 What the call contains

The call is the union of two things:

1. **System prompt** — persona, behavioral directives, domain knowledge. The text that tells the crystal who it is and how it should behave.
2. **Hyperparameters** — temperature, top_p, max_tokens, stop sequences, sampling configuration. The knobs that control how the crystal generates.

That's it. The call is identity. It answers two questions: *who is this entity?* and *how does it think?* Notice what is absent: gate definitions. The crystal needs to know what gates are available — but that knowledge comes from the circle, not the call. The circle owns its gates and is responsible for presenting them to the crystal as tool definitions at query time. This is the circle's job because gates are the circle's components: the circle registers them, the circle executes them, and the circle renders them for the crystal to perceive.

Why does this matter? Because it keeps the call small and separable. The same call — the same identity — can be placed into different circles with different gate sets. A "research assistant" call works in a circle with `fetch` and `read` gates, and equally in a circle with `search` and `browse` gates. The call does not change. The circle presents its own capabilities.

> **CALL-3**: Gate definitions are the circle's responsibility. The circle MUST present its registered gates to the crystal as tool definitions at query time. The call MUST NOT contain gate definitions.

This is a clean separation. The call shapes the crystal's identity. The circle shapes its capabilities. Together they form the full context the crystal receives — but they are independently configurable, and that independence is the point.

### 3.2 Immutability and identity

The call is fixed. You can create a new cantrip with a different call, but you can't mutate the call of an existing one. This gives you clean axes of variation:

Same crystal + different call = different entity behavior. Change the system prompt, and the same model reasons differently about the same task. Change the temperature, and it explores differently.

Same crystal + same call + different circle = different capabilities. The entity has the same identity but different gates, a different medium, different wards.

Same crystal + same call + same circle + different intent = different episode. The cantrip is the same recipe. The intent is what varies between runs.

> **CALL-2**: If a system prompt is provided, it MUST be the first message in every context sent to the crystal. It MUST be present in every query, unchanged.

The system prompt anchors the crystal's behavior across every turn of the loop. It's the one piece of context that never moves, never compresses, never gets folded away. The entity always knows who it is.

### 3.3 What the call is not

The call is small and fixed. The circle holds the state. The entity explores it through code. This distinction matters enough to be worth stating clearly.

Dynamic context — retrieved documents, injected state, programmatic insertions that change per turn — is not part of the call. These are circle state, accessed through gates. A cantrip that processes a thousand documents doesn't stuff them into the system prompt. It places them in the circle as data the entity can read, query, and navigate through code. The call tells the entity who it is. The circle tells it what it can do. The circle contains what it works with.

This is the core architectural insight: context belongs in the environment, not in the prompt. The prompt is small, fixed identity. The environment is large, rich, and explorable. When the entity needs information, it reaches for it through a gate — reading a file, querying a data structure, inspecting a variable that persists in the sandbox between turns. The call doesn't grow. The circle does.

### 3.4 The call in the loom

The loom records everything (Chapter 6 tells the full story). The call's role in the loom is simple: it's the root.

> **CALL-4**: The call MUST be stored in the loom as the root context. Every thread starts from the same call.

When you fork a thread — branching from an earlier turn to explore a different path — both branches share the same call. They diverge in experience but not in conditioning. The entity always retains its full identity.

> **CALL-5**: Folding (context compression) MUST NOT alter the call. The entity always retains its full identity. Only the trajectory (turns) may be folded.

When context grows too large and older turns must be compressed to fit the crystal's window, the call is exempt. The system prompt and hyperparameters survive folding intact. So do the circle's gate definitions — the circle re-presents them on every query. The entity may lose detailed memory of what it did on turn three, but it never loses its sense of who it is and what it can do.

---

## Chapter 4: The Circle

The crystal thinks. The call shapes. The circle is where thinking meets the world.

Everything up to now has been preparation. The crystal is a function — messages in, response out. The call conditions it — who you are, how you behave, what you can do. But neither does anything until there is somewhere to act. The circle is that somewhere. It receives what the entity writes, executes it, and returns what happened. It is the ground the entity walks on, and the ground pushes back.

### 4.1 What a circle is

A circle is anything that receives the entity's output and returns an observation. Every circle has a **medium** — the substrate the entity works *in*. Think of it like an artist's medium: oil, marble, code. The medium is not a gate — it is the inside. Gates cross into it from outside. Circles exist on a spectrum of expressiveness determined by their medium, and the cantrip vocabulary applies across that entire spectrum. The simplest circle is one you already know.

A human circle is a conversation. The medium is natural language. You type something to ChatGPT, the model responds, your next message is shaped by what it said. You are the environment. Your judgment is the pushback. The action space is just conversation — there are no gates beyond the implicit exchange, no sandbox, no persistent state. The formula collapses: A is whatever the model can say.

A tool-calling circle adds gates. The entity invokes JSON functions — `read`, `fetch`, `search` — and receives structured results. The medium is still conversation — structured conversation, but conversation. There is no sandbox, no primitives the entity can compose on its own. The action space is just the gate set: A = G minus W. This is how most agent systems work today. It is valid and common.

A code circle gives the entity a full execution context — a sandbox where it can write and run arbitrary programs, with gates to the outside world and wards that constrain what is allowed. The medium is code. The entity writes it. The sandbox executes it. The result comes back as an observation. Variables persist between turns. Errors are visible. The ground pushes back with truth, not opinion. The action space is the full formula: A = (M + G) minus W. The entity can combine the medium's primitives and gates in ways nobody enumerated in advance — loops that call gates conditionally, variables that store gate results for later turns, data pipelines composed on the fly. This compositionality is what makes code circles the most expressive case.

These are points on a spectrum, not categories with hard boundaries. A tool-calling agent that generates JSON is closer to a code circle than a chat window is, but it lacks the compositionality of a real sandbox. A code circle with no gates beyond `done` is more constrained than a tool-calling agent with twenty gates, but its action space is still richer because its medium is a programming language. What varies is the circle's design. What stays the same is the vocabulary: crystal, call, circle, gate, ward, entity, turn, thread, loom. The rest of this chapter focuses on code circles — the most expressive case, where the most interesting design questions arise — but the concepts apply everywhere.

### 4.2 What the entity can do

Now that the spectrum is clear, let's look at what happens inside the most expressive case. The entity's capabilities in a code circle are described by a formula:

```
A = (M + G) − W
```

**M** is the medium. Whatever the circle's substrate provides — in a code circle, that means builtins, math, strings, control flow, data structures, standard library. In a browser circle, it means the DOM and its APIs. In a conversation circle, it means natural language. The medium is the set of primitives the entity can compose without crossing any boundary. Think of it like an artist's medium: oil, marble, code. It determines what the entity works *in*, and different mediums afford different kinds of expression.

**G** is the set of registered gates. Gates are host functions that cross the circle's boundary into the outside world: reading files, making HTTP requests, spawning child entities. They are the entity's exits from the medium.

**W** is the set of wards. Wards are restrictions that remove or constrain elements of M and G. A ward might remove a gate entirely, restrict a gate's reach, cap the number of turns, or limit resource consumption.

The action space A is what remains after wards have carved away what is forbidden. The entity starts with the full surface of the medium plus every registered gate. Wards subtract from that surface. What is left is what the entity can do.

This is not a metaphor. It is how the system actually works. The formula reveals something important: when the medium is a programming language, the action space is compositional. The entity can combine primitives and gates in ways nobody enumerated in advance. It can write a loop that calls a gate conditionally. It can store a gate's result in a variable and use it three turns later. It can compose gates with medium primitives in any way the medium allows. This compositionality is what separates a code circle from a tool-calling interface — and it is why the rest of this chapter focuses on the code circle case.

> **CIRCLE-1**: A circle MUST provide at least the `done` gate.

The `done` gate is the minimum. Without it, the entity has no way to signal that it believes the task is complete. Every other gate is optional and domain-specific.

> **CIRCLE-8**: The `done` gate MUST accept at least one argument: the answer/result. When `done` is called, the loop terminates with that result.

### 4.3 Gates

If the circle is where the entity acts, gates are where the entity reaches beyond it. Inside the sandbox, the entity operates freely within the medium — writing code, storing variables, building data structures. Gates are the crossing points through the circle's boundary: how effects reach the outside world, and how outside information reaches the entity.

Common gates:
- `done(answer)` — signal task completion, return the answer
- `call_entity(intent, config?)` — cast a child cantrip on a derived intent
- `call_entity_batch(intents)` — cast multiple child cantrips in parallel
- `read(path)` — read from the filesystem
- `write(path, content)` — write to the filesystem
- `fetch(url)` — HTTP request
- `goto(url)` / `click(selector)` — browser interaction

Each gate closes over environment state — it carries configuration that the entity never sees and never needs to. A `read` gate knows its filesystem root. A `call_entity` gate holds a reference to the crystal it will use for child entities. A `fetch` gate may carry timeout configuration or authentication headers. You configure what each gate has access to when you construct the circle — not when the entity invokes the gate.

> **CIRCLE-10**: Gate dependencies (injected resources) MUST be configured at circle construction time, not at gate invocation time.

This is dependency injection for gates. The entity calls `read("data.json")` without knowing or caring where the filesystem root is. The gate knows. The circle was prepared before the entity appeared.

> **CIRCLE-3**: Gate execution MUST be synchronous from the entity's perspective — the entity sends a gate call, the circle executes it, the observation returns before the next turn begins.

The entity never has to wonder whether a gate has finished. It calls a gate, receives the result, and proceeds. The implementation may do asynchronous work behind the scenes, but from the entity's perspective, every gate call is a function that returns a value.

> **CIRCLE-4**: Gate results MUST be returned as observations in the context. The entity MUST be able to see what its gate calls returned.

> **CIRCLE-5**: If a gate call fails (throws an error), the error MUST be returned as an observation, not swallowed. The entity MUST see its failures.

Swallowing errors is a common implementation mistake, and it silently cripples the entity. If a file does not exist, the entity needs to see the error so it can try a different path. If a network request times out, the entity needs to know so it can retry or adjust its strategy. Errors are not failures to be hidden. They are observations. They carry information the entity needs to learn from.

Here is the canonical shape of a gate result:

```
GateCallRecord {
  tool_call_id: string   // correlates to the crystal's tool_call
  gate: string           // gate name
  ok: boolean            // success or failure
  result?: any           // return value on success
  error?: { name: string, message: string }  // on failure
}
```

The observation per turn is an ordered list of `GateCallRecord` objects — one per gate call in the utterance. This is what the entity sees when it looks at what happened. The `tool_call_id` links each result back to the crystal's original invocation, so the entity (and the crystal on the next turn) can match responses to requests unambiguously. When a gate succeeds, `ok` is true and `result` contains the return value. When a gate fails, `ok` is false and `error` carries a structured description of what went wrong.

> **CIRCLE-7**: If multiple gate calls appear in a single utterance, the circle MUST execute them in order and return each result as an entry within that turn's single composite observation. The observation is one object per turn (preserving LOOP-1's strict alternation), with an ordered list of per-gate results inside it. Implementations MAY execute independent gate calls in parallel.

### 4.4 Wards

Gates open the circle outward. Wards close it back in. Where gates expand the entity's reach beyond the sandbox, wards contract it. They are subtractive — they remove or constrain elements of the full action space, not permissions granted from nothing.

Consider the varieties. A ward that removes a gate shrinks G: "this circle has no network access" means `fetch` is not registered. A ward that restricts a gate's reach narrows what the gate can do: "read only from /data" means the `read` gate rejects paths outside that directory. A ward that constrains the medium shrinks M: "no eval," "no network APIs in the sandbox." A ward that caps turns bounds the episode: "max 200 turns" means the loop is cut off if the entity has not called `done` by then. A ward that limits resources prevents runaway consumption: "max 1M tokens," "timeout after 5 minutes."

> **CIRCLE-2**: A circle MUST have at least one ward that guarantees termination (max turns, timeout, or similar). A cantrip that can run forever is invalid.

This is the safety net. The `done` gate is how the entity chooses to stop. A termination ward is how the environment forces a stop when the entity does not. Both are required — one is the mechanism of completion, the other is the guarantee against infinite loops.

> **CIRCLE-6**: Wards MUST be enforced by the circle, not by the entity. The entity cannot bypass a ward. Wards are environmental constraints.

This is the critical distinction, and it is worth sitting with. A ward is not a polite request. It is not an instruction in the system prompt that the entity might choose to ignore. It is a structural property of the environment. If `fetch` is not registered, the entity cannot make HTTP requests no matter what it writes. If the turn limit is 200, turn 201 does not happen. The entity cannot reason its way around a ward because the ward operates outside the entity's control.

The philosophical orientation here follows the Bitter Lesson: abstractions that constrain the action space fight against model capability. The entity should start with the fullest possible action space. Then you ward off what is dangerous. You do not build up from nothing — you carve down from everything. This is why they are called wards, not permissions.

When circles compose — a parent spawning a child via `call_entity` — their wards compose too. The child inherits the parent's wards, and the composition is conservative: the child can never be *less* restricted than its parent.

> **WARD-1**: When circles compose, numeric wards (max turns, max tokens, max depth) MUST take the `min()` of parent and child values. Boolean wards (allow network, allow filesystem) MUST take logical `OR` of restrictions — if either circle forbids it, it is forbidden. A child circle's wards can only tighten, never loosen, the parent's constraints.

### 4.5 Tool-calling circles

Not every circle needs a sandbox. When the crystal uses structured tool calls — JSON function invocations rather than code — the medium is conversation and the action space simplifies to A = G minus W, as described in §4.1. The entity can only invoke gates by name with JSON arguments. There are no medium primitives to compose with beyond natural language. This is less expressive than a code circle, but it is simpler to implement and sufficient for many tasks.

Implementations MUST support tool-calling circles. Implementations SHOULD support code circles.

### 4.6 Circle-mediated perception

The circle does more than execute code. It determines what the entity perceives. This is a subtler role than it first appears.

The call and the intent are always present — they are the entity's fixed orientation, delivered on every turn (as established in LOOP-5). Everything beyond that is the circle's decision. The circle controls how prior experience is presented to the entity, and this is a design choice with real consequences.

The simplest approach is the one most agent systems use today: stuff the full history of prior turns into the prompt as a growing message list. Every utterance and every observation, appended in order, visible to the crystal on every query. This works. It is also the most expensive design, because the prompt grows with every turn, and the crystal re-reads everything it has already seen.

In a code circle, there is a more interesting option. The entity can access prior state through code — reading variables that persist in the sandbox, querying data structures it built on earlier turns, inspecting files it wrote to disk. The message history can be slim or even absent, because the entity's knowledge lives in the environment as program state rather than in the prompt as text. This is the principle from §3.3 in action: context belongs in the environment, not in the prompt.

Both designs are valid. A circle that presents full message history is conformant. A circle that stores state as program variables the entity accesses through code is also conformant. The spec does not mandate one approach over the other. What matters is that the call and intent are always present, and that the entity can perceive the consequences of its prior actions — however the circle chooses to make those consequences available.

#### The three message layers

Every query the circle assembles for the crystal has three layers, in this order:

1. **Call** (identity). The system prompt and hyperparameters — who the entity is and how it thinks. This is the call, unchanged from construction (CALL-1, CALL-2). It does not describe what the entity can do. It describes what the entity *is*.

2. **Capability presentation** (circle-derived). What the crystal can do in this circle — a description of the medium, the registered gates, and their contracts. The circle generates this layer from its own configuration: its medium, its gate set, and any constraints the entity should know about. In a code circle, this might be a `### HOST FUNCTIONS` section listing the gates projected into the sandbox. In a tool-calling circle, the gate definitions passed as `tools` serve this role. The capability presentation changes when the circle is reconfigured — add a gate, change the medium, alter a ward — but never during a cast. It is downstream of identity and upstream of intent.

3. **Intent** (goal). What the entity is pursuing. The first user message, immutable for the lifetime of the cast (INTENT-3).

This ordering is not accidental. Identity is fixed at construction. Capabilities are derived from the circle and fixed at cast time. The intent varies per cast. Each layer is more specific than the last, and each is owned by a different component: the call owns identity, the circle owns capabilities, and the caller owns intent.

> **CIRCLE-11**: The circle MUST generate a capability presentation for the crystal — a description of the medium, registered gates, and their contracts. This presentation MUST be included in the crystal's context on every query, between the call and the intent. Gate definitions in the `tools` parameter and capability documentation in the prompt are both valid forms of this presentation.

Notice what this means for CALL-3: gate definitions are the circle's responsibility, not the call's. The call does not know what gates exist. The circle registers them, executes them, and presents them to the crystal. The call stays small and separable — the same identity in different circles with different capabilities.

### 4.7 Circle state

The circle maintains state between turns. This is what makes the loop a loop rather than a series of disconnected invocations. The state comes in two forms.

**Sandbox state** is what lives inside the execution context — variables, data structures, intermediate results that the entity created through code and that persist across turns within the same entity.

> **CIRCLE-9**: In a code circle, sandbox state MUST persist across turns within the same entity. A variable set in turn 3 MUST be readable in turn 4.

Without this guarantee, the entity cannot build on its own work. Each turn would start from scratch, and the entity would have to re-derive everything it knew from the message history alone. Persistent sandbox state is what makes a code circle a code circle — the entity accumulates not just conversation but computation.

**External state** is what lives outside the sandbox but is accessible through gates — the filesystem, a database, browser DOM, whatever resources the gates have been configured to reach. External state may be shared across entities or persist beyond a single entity's lifetime. Sandbox state is private to the entity and dies when the entity terminates.

### 4.8 Security

Security in the circle model is a question of warding. The tools are the same ones you have been reading about. What changes is the stakes.

The canonical threat is the lethal trifecta: a circle that has access to private data, processes untrusted content, and can communicate externally. Any two of these together are manageable. All three in the same circle create a path for data exfiltration — untrusted content instructs the entity to read private data and send it out through a network gate.

The defense is subtractive — the same subtractive principle that governs all warding. Remove one leg of the trifecta by warding off the relevant gate. A circle that processes untrusted content and reads private data but cannot make network requests is safe against exfiltration. A circle that has network access and reads private data but never processes untrusted input is also safe. Alternatively, isolate capabilities across separate circles — one circle handles untrusted content with network access but no private data, another handles private data with no network access.

**Prompt injection** is the specific threat that makes careful circle design non-optional. Untrusted content processed by the entity — user-supplied documents, web pages, emails, any data the entity did not generate itself — may contain instructions that attempt to override the call. The entity cannot reliably distinguish between its own instructions and adversarial text embedded in its input. This is not a bug in any particular model. It is a structural property of systems that process natural language: the control channel and the data channel are the same channel.

Wards cannot prevent the entity from being influenced by its input — they can only prevent the entity's actions from reaching dangerous gates. The defense against prompt injection is circle design: isolate the processing of untrusted content from circles that have access to sensitive data or external communication. A child entity that summarizes untrusted documents should not have the `fetch` gate. A circle that handles outbound email should not process unvetted attachments. The trifecta framework gives the pattern: remove one leg, and the injection has less path to harm.

Security is not a feature you bolt on. It is what you carve away. Drawing good circles — choosing which gates belong together and which must be separated — is the practitioner's art.

---

## Chapter 5: Composition

So far, every entity has been alone. One crystal, one circle, one intent. The entity acts, the environment responds, the loop runs until it's done. This is enough for many tasks. But some tasks are too large for one entity, or too naturally decomposable, or too parallelizable. The entity needs to delegate.

In most agent frameworks, delegation is a special mechanism — a workflow node, a handoff protocol, a message passed through an orchestrator. In a code circle, delegation is a function call. The entity writes `call_entity({ intent: "summarize this document" })` and a child entity appears in its own circle, pursues that sub-intent, and returns a result. The parent blocks until the child finishes. From the parent's perspective, it called a function and got a value back. From the loom's perspective, a subtree just grew.

This matters because the entity writes code, and code composes. The entity does not delegate through a configuration file or a workflow graph. It delegates inside loops, behind conditionals, as part of programs it writes on the fly. Composition through gates is composition through code, which means the entity can invent delegation patterns its designers never enumerated — recursive intelligence, not an API call.

Watch how intent spawns sub-intents. The parent entity is pursuing some goal — "fix my application" — and discovers, mid-task, that it needs to understand a database schema, refactor an authentication module, and rewrite a set of tests. Each of these is a desire born from the parent's desire. The parent's intent does not change — it is still trying to fix the application. But the work of fixing the application generates child intents, and `call_entity` is the gate through which they are pursued.

### 5.1 The `call_entity` gate

```
result = call_entity({
  intent: "Summarize this document",
  context?: any,         // data injected into child's circle
  system_prompt?: string, // child's call (defaults to parent's)
  max_depth?: number      // recursion limit ward
})
```

The child entity gets its own circle, its own context, its own turn sequence. It does not inherit the parent's conversation history — it starts fresh, with only the sub-intent and whatever data the parent passes through the `context` field. This clean separation is what makes delegation composable rather than fragile.

> **COMP-4**: A child entity MUST have its own independent context (message history). The child does not inherit the parent's conversation history.

The child's circle is carved from the parent's — the subtractive principle from Chapter 4 applied to composition. The parent cannot grant gates it does not have. A parent entity with no `fetch` gate cannot give its child network access. The child's circle is always a subset.

> **COMP-1**: A child entity's circle MUST be a subset of the parent's circle. You cannot grant gates the parent doesn't have.

But the child's crystal and call may differ. You might send a cheaper, faster crystal to handle a simple sub-task, or provide a different system prompt that specializes the child for the work at hand. The circle is inherited subtractively. Everything else can be configured per child.

> **COMP-7**: The child's crystal MAY differ from the parent's crystal (if the `call_entity` config specifies a different one). The child's call MAY differ. Only the circle is inherited (subtractive).

The parent blocks while the child runs. This is synchronous from the parent's perspective — the same contract as any other gate (CIRCLE-3). Think about what this means: the child entity lives its entire life within the parent's turn. It appears, acts across however many turns it needs, terminates or is truncated, and the parent receives the result. A whole entity lifecycle, nested inside a single gate call.

> **COMP-2**: `call_entity` MUST block the parent entity until the child completes. The parent receives the child's result as a return value.

If the child fails — throws an error rather than calling `done` — the error comes back as the gate result. The parent sees it as an observation and decides what to do. A child's failure does not kill the parent.

> **COMP-8**: If a child entity fails (throws an error, not `done`), the error MUST be returned to the parent as the gate result. The parent MUST NOT be terminated by a child's failure.

> **COMP-9**: When a parent entity is terminated or truncated, all active child entities MUST be truncated with reason `parent_terminated`. Child turns up to the cancellation point are preserved in the loom. The child's truncation is recorded as any other truncation — the loom distinguishes it only by the reason field.

### 5.2 Batch composition

Sometimes one child is not enough. `call_entity_batch` spawns multiple children in parallel:

```
results = call_entity_batch([
  { intent: "Summarize chunk 1", context: chunk1 },
  { intent: "Summarize chunk 2", context: chunk2 },
  { intent: "Summarize chunk 3", context: chunk3 },
])
```

The children execute concurrently. Results are returned as an array in the order they were requested, not in the order the children finish. This gives the parent a predictable interface — `results[0]` always corresponds to the first intent, regardless of which child was fastest.

> **COMP-3**: `call_entity_batch` MUST execute children concurrently. Results MUST be returned in request order, not completion order.

### 5.3 Composition as code

Here is where the code circle earns its keep. The power of composition in a code circle is that it composes with the medium. The entity does not just call `call_entity` once — it calls it inside loops, behind conditionals, as part of data pipelines it writes on the fly. Data lives in the circle as a variable, the entity explores it through code, and sub-entities handle the pieces.

```
// Inside the entity's code (in the sandbox):
const chunks = splitIntoChunks(context.documents, 100);
const summaries = call_entity_batch(
  chunks.map(chunk => ({
    intent: "Extract key findings",
    context: { documents: chunk }
  }))
);
const final = summaries.join("\n");
done(final);
```

The data never enters the prompt. The entity writes a program that partitions, delegates, and synthesizes. The number of children is determined at runtime by the data, not at design time by the developer. This is what separates composition-through-code from a static workflow graph.

### 5.4 Depth limits

Composition is recursive — a child entity has the `call_entity` gate in its circle (inherited from the parent), so it can spawn children of its own. Children spawning children, all the way down. Without a limit, this is infinite recursion. Every cantrip has a `max_depth` ward to prevent it.

- Depth 0 means no `call_entity` allowed — the gate is warded off
- Each child's depth limit is the parent's depth minus 1
- Default depth is 1 (the entity can spawn children, but those children cannot spawn their own)

> **COMP-6**: When `max_depth` reaches 0, the `call_entity` and `call_entity_batch` gates MUST be removed from the circle (warded off). Attempts to call them MUST fail with a clear error.

This is warding applied to recursion. The depth limit does not tell the entity to stop delegating — it removes the gate entirely, making delegation structurally impossible at that level.

### 5.5 Composition in the loom

Every child entity's turns are recorded in the same loom as the parent. The child's turns form a subtree, with the child's root turn referencing the parent turn that spawned it. (The loom itself is the subject of the next chapter. For now, what matters is that delegation leaves a complete trace.)

```
Parent turn 1
Parent turn 2 (calls call_entity)
├── Child turn 1
├── Child turn 2
└── Child turn 3 (done)
Parent turn 3 (receives child result)
```

The parent's next turn (after the child completes) has `parent_id` pointing to the parent's previous turn, not to the child. The child subtree branches off and rejoins — a side excursion in the parent's thread. Walk the parent thread and you see the delegation as a single step. Walk the child subtree and you see every decision the child made. Both views exist because the loom records everything.

> **COMP-5**: A child entity's turns MUST be recorded in the loom as a subtree. The child's root turn references the parent turn that spawned it.

---

## Chapter 6: The Loom

Every chapter so far has produced turns. The loop runs, the entity acts, the circle responds, state accumulates. Turn after turn, the entity builds context, makes decisions, pursues its intent through code. Then the loop ends — `done` is called, or a ward triggers — and the entity is gone.

Where did the turns go?

They went into the loom. Every turn — every utterance, every observation, every gate call and its result — was being recorded as it happened, appended to a growing tree. One path through that tree is a thread. All threads, across all runs of a cantrip, form the loom.

Here is the reveal that has been implicit since page one: the loom was accumulating from the first turn of Chapter 1. When the entity emerged and started acting, the loom was already there, writing down everything. When composition spawned child entities in Chapter 5, their turns went into the same loom, branching off the parent's thread as subtrees. The structure described in the last five chapters — the loop, the crystal's responses, the circle's observations, the parent-child relationships of composed entities — is the structure of the loom. Everything was being recorded. The loom is what all of it produces.

### 6.1 Turns as nodes

Start with the atomic unit. Each turn is stored as a record:

```
Turn {
  id: string             // unique identifier
  parent_id: string?     // null for root turns
  cantrip_id: string     // which cantrip produced this turn
  entity_id: string      // which entity was acting
  role: string           // "crystal" | "call" | "fold"
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

The `role` field distinguishes what produced the turn. Most turns are `"crystal"` — the entity acted and the circle observed. A `"call"` turn records the initial system context (the call as root). A `"fold"` turn is a synthetic summary injected by folding (§6.8) — it replaces a range of earlier turns in the entity's working context but is itself recorded so the loom traces exactly when and how context was compressed.

None of this is optional bookkeeping. Token counts are how you track cost. Timing is how you find bottlenecks. The reward slot — empty by default — is how the loom becomes training data. Every field on the turn record exists because something downstream needs it.

### 6.2 Threads

Turns link to their parents. Follow those links from any leaf back to the root and you have a thread — one complete path through the turn tree. Threads are implicit. They emerge from the parent references on turns. You do not store threads separately. You store turns with parent pointers, and a thread is any root-to-leaf path you can walk.

A thread has exactly one of these terminal states:
- **Terminated**: the final turn called `done`
- **Truncated**: a ward stopped the entity
- **Active**: the entity is still running (only during execution)

> **LOOM-7**: The loom MUST record whether each terminal turn was terminated (entity called `done`) or truncated (ward stopped the entity).

This distinction — which first appeared in Chapter 1 — becomes load-bearing here. A terminated thread is a completed episode: the entity finished its work, and the final state represents a conclusion. A truncated thread is an interrupted episode: the entity was cut off, and its final state should not be treated as an endpoint because it was not one. Training on the loom must respect this difference. Terminated threads have natural endpoints. Truncated threads do not.

### 6.3 The loom

Now step back and see the whole structure. The loom is the tree of all turns produced by a cantrip across all its runs. Cast the same cantrip on ten different intents and you get ten threads in one loom. Fork from turn seven of one thread and you get a branch — two threads sharing a common prefix, diverging from the fork point. Compose with `call_entity` and child subtrees grow inside parent threads. The loom holds all of it.

This is the most valuable artifact a cantrip produces. It is simultaneously:
- **The debugging trace** — walk any thread to see every decision the entity made
- **The entity's memory** — context for forking, folding, and replaying
- **The training data** — each turn is a (context, action, observation) triple, each thread is a trajectory, reward slots are already there
- **The proof of work** — evidence of what the entity did and why

### 6.4 Reward and training data

This is the loom's deepest purpose, and the reason its tree structure matters. Each turn is a (context, action, observation) triple. Each thread is a trajectory. The reward slots are already there. The loom is not merely a replay buffer to be sampled from. It is a training data store — and its tree structure is shaped for the comparative methods that need it most.

The loom stores a reward slot on every turn. What fills it is up to the implementation — and there are several natural options.

- **Implicit reward** — did the gate succeed? Did the code throw? Gate-level success/failure is a natural per-turn signal.
- **Explicit reward** — a score attached after the fact. A human rates the thread. An automated verifier checks the output. A verifier entity — itself a cantrip — evaluates the work.
- **Shaped reward** — intermediate rewards computed by a scoring function that is part of the circle definition. The rubric is part of the environment.

For in-context learning within a session, implicit reward is enough. The entity sees what worked and what did not in its own context window and adjusts. For training across sessions — reinforcement learning on the loom — you need explicit reward annotation.

Modern LLM-RL methods — GRPO, RLAIF, best-of-N sampling — do not learn from single trajectories in isolation. They learn by comparing multiple trajectories of the same task. GRPO (Group Relative Policy Optimization) generates N completions for the same prompt, ranks them, and uses the relative ranking as the reward signal. No absolute reward model is needed. The comparison itself is the learning signal.

The loom affords exactly this structure. Fork from the same turn N times — or cast the same cantrip on the same intent N times — and you get N threads that share a common origin but diverge in execution. Rank them by outcome — which thread solved the task? which was most efficient? which produced the cleanest code? — and the ranking becomes a reward signal. The loom's tree structure provides the trajectory data that comparative RL methods need.

```
// Same intent, three runs:
//
// Intent: "Fix the auth bug"
//
// Thread A: 12 turns, fixed the bug, clean solution    -> rank 1
// Thread B: 18 turns, fixed the bug, messy refactor    -> rank 2
// Thread C: 25 turns, truncated by ward, bug not fixed -> rank 3
//
// The ranking IS the reward signal.
// No reward model needed. Just comparison.
```

This is not a feature bolted onto the loom after the fact. It is what the loom's structure naturally affords. A flat log of turns could support single-trajectory training. The tree structure — with forking, branching, and multiple threads from the same origin — supports comparative training. The loom is a training data store shaped for comparative methods, not just a replay buffer.

(Multi-turn credit assignment remains an active research problem. The loom provides the trajectory structure these methods need; the credit assignment and reward propagation are the responsibility of whatever training infrastructure consumes it.)

> **LOOM-10**: The loom MUST support extracting any root-to-leaf path as a thread (trajectory) for export, replay, or training.

The sections that follow describe the loom's structural mechanics — storage, forking, composition, context management — that make all of this possible.

### 6.5 Storage

The storage model is simple: turns are appended as they happen. The loom is append-only.

> **LOOM-3**: The loom MUST be append-only. Turns MUST NOT be deleted or modified after creation. Reward annotation is the exception — reward MAY be assigned or updated after creation.

The reference storage format is JSONL — one JSON object per line, one turn per line, appended in chronological order. Implementations MAY use other storage backends as long as the append-only semantic is preserved. What matters is that no turn is ever lost, rewritten, or silently dropped. The loom is the ground truth.

### 6.6 Forking

Here is where the tree structure becomes more than a data format. Forking creates a new turn whose parent is an earlier turn in the tree, diverging from the original continuation.

```
// Original thread: turns 1 -> 2 -> 3 -> 4 -> 5
// Fork from turn 3:
// turns 1 -> 2 -> 3 -> 4 -> 5   (original thread)
//                   \-> 6 -> 7   (forked thread)
```

A forked entity starts with the context from the fork point — all turns from root to the fork turn. The original thread is untouched. The new thread grows independently.

> **LOOM-4**: Forking from turn N MUST produce a new entity whose initial context is the path from root to turn N. The original thread MUST be unaffected.

Implementations MUST declare how sandbox state is captured at fork points. Two strategies are valid. **Snapshot** serializes the sandbox's current state — variables, data structures, file contents — into a portable image that the forked entity inherits. **Replay** re-executes the entity's code from the root turn up to the fork point, reconstructing the sandbox state from scratch. Both produce the same logical state; they differ in cost and in what they can capture. Snapshot is fast but may struggle with imperative state that resists serialization — open file handles, live network connections, mutable objects with circular references. Replay is slow but faithful, because it reconstructs state through the same code that built it. The loom MUST record which strategy was used for each fork, so that consumers know how the forked entity's initial state was established.

Forking is not an environment reset. The forked entity continues from the accumulated state at the fork point. It has the same context the original entity had at that moment — the same variables in the sandbox, the same history of actions and observations. What differs is the future. The original entity went one way from turn 3. The forked entity goes another way. Both paths are recorded. Both threads persist.

This is where the loom's tree structure earns its keep. A flat log could record one thread. A tree records every branch, every alternative path, every "what if we had gone left instead of right." The loom is a map of the roads taken and not taken. Forking is how you explore new roads from old waypoints. And those branching paths — as §6.4 described — are exactly what comparative RL methods need.

### 6.7 Composition in the loom

Chapter 5 described composition from the parent's perspective — a gate call that blocks and returns a result. From the loom's perspective, it is the same mechanism as forking. When `call_entity` spawns a child entity, the child's turns form a subtree rooted at the parent turn that spawned it. A new branch grows from an existing turn — except this branch is a child entity pursuing a sub-intent, and its result flows back into the parent's thread.

> **LOOM-8**: Child entity turns from `call_entity` SHOULD be stored in the same loom as the parent, with parent references linking them to the spawning turn. Implementations that store child turns in a separate loom MUST still record the parent-child relationship.

Everything stays in one tree. The parent's thread, the child's subtree, a grandchild's sub-subtree — all recorded in the same loom with `parent_id` pointers connecting them. The child's first turn has a `parent_id` pointing to the parent turn that spawned it. Subsequent child turns chain to each other as usual. When the child completes, the parent's next turn has a `parent_id` pointing to the parent's *previous* turn — not to any child turn. The child subtree branches off and rejoins. Walking any root-to-leaf path through the tree yields one thread — one trajectory. Some threads pass only through parent turns. Others descend into child subtrees. The loom does not distinguish between "main work" and "delegated work." It records turns, and the structure emerges from their relationships.

> **LOOM-12**: The loom SHOULD be a single unified tree. When all entities — parent, child, grandchild — record their turns into the same tree, a thread is any root-to-leaf path, and the tree's branching structure encodes the full delegation hierarchy.

### 6.8 Folding and compaction

Context grows. Every turn adds to what the entity has seen and done. Eventually, the accumulated context approaches the crystal's window limit, and something must give. There are two responses to this pressure, and understanding their difference matters.

**Folding** is the deliberate integration of loom history into circle state. Instead of keeping every prior turn in the message list for the crystal to re-read, the entity — or the circle on the entity's behalf — takes the substance of earlier turns and encodes it as state the entity can access through code: variables, data structures, summaries stored in the sandbox. The full turns remain in the loom. The entity's working context shrinks because the knowledge now lives in the environment rather than in the prompt. This is the principle from §3.3 made operational at scale.

> **LOOM-5**: Folding MUST NOT destroy history. The full turns MUST remain accessible. Folding produces a view, not a mutation.

> **LOOM-6**: Folding MUST NOT compress the call or the circle's gate definitions. The system prompt, hyperparameters, and gate definitions MUST always be present in the entity's context.

**Compaction** is the crude fallback. When folding is not available or not sufficient — when the message window is still too large despite the entity's best efforts to move state into the circle — compaction truncates or summarizes the oldest turns in the prompt. A sliding window keeps the last N turns and drops the rest. A summary replaces a range of turns with a compressed digest. The entity loses direct access to the detail of those turns, though the full history persists in the loom underneath.

```
// Folding: history becomes circle state
// Entity's context: [call] [intent] [recent turns]
// Circle state: variables holding synthesized knowledge from earlier turns
// Loom: all turns intact

// Compaction: oldest turns are summarized in the prompt
// Entity's context: [call] [intent] [summary of turns 1-20] [turns 21-30]
// Loom: all turns intact
```

Both techniques preserve the loom — neither destroys history. The difference is in how the entity relates to its past. Folding gives the entity programmatic access to its history through code. Compaction gives the entity a lossy summary in the prompt. Think of folding as a design choice and compaction as a pressure valve.

**Who triggers folding.** The circle or harness triggers folding automatically, per PROD-4. The entity does not decide when to fold — it may not even know it has happened, though it MUST be able to tell (see fidelity below). The circle monitors context size against the crystal's advertised window and folds when the threshold is crossed.

**Trigger threshold.** Folding SHOULD trigger when the entity's accumulated context exceeds 80% of the crystal's advertised window. The remaining 20% provides headroom for the next turn's utterance and observation. Implementations MAY use a different threshold, but MUST document it.

**What form the folded state takes.** Folding replaces a range of detailed turns in the entity's working context with a summary node — a single message that captures the substance of those turns in compressed form. The full turns remain in the loom, untouched. The summary node is injected into the prompt in place of the turns it replaces. In a code circle, folding MAY also encode summarized state as variables in the sandbox, giving the entity programmatic access to its compressed history.

**Fidelity guarantees.** The entity MUST be able to distinguish folded context from unfolded context. A folded summary MUST be explicitly marked — for example, by a prefix like `[Folded: turns 1-20]` or an equivalent structural marker. The entity should never mistake a summary for a verbatim record of what happened. This marking is what preserves the entity's epistemic honesty: it knows what it remembers directly and what it knows only through summary.

**A worked example.** An entity has run for 30 turns. The crystal's window is 128k tokens. At turn 25, the accumulated context — call, intent, and 24 turns of history — reaches 102k tokens (80% of 128k). The circle triggers folding.

```
// Before folding (entity's working context):
// [call] [intent] [turn 1] [turn 2] ... [turn 24] [turn 25 utterance]
// Total: ~102k tokens

// After folding:
// [call] [intent] [folded summary: turns 1-18] [turn 19] ... [turn 25 utterance]
// Total: ~45k tokens
//
// The summary replaces turns 1-18 with a ~3k token digest.
// Turns 19-25 remain verbatim — recent context is preserved in full.
// The loom still contains every turn in complete detail.
```

The call and the circle's gate definitions are exempt from both techniques. The system prompt, the hyperparameters, and the gate presentations — these survive intact regardless of how aggressively the context is managed. The entity may lose detailed memory of what it did on turn three, but it never loses its sense of who it is and what it can do.

### 6.9 The loom as entity-readable state

So far, the loom has been a record that the entity produces but cannot see. It can also face inward. A circle MAY expose the loom — or part of it — as a readable object in the entity's sandbox. When it does, the entity can access its own history through code.

This is a circle design choice, not a mandate. Some circles expose the full loom as a queryable variable. Others expose just the current thread. Others expose nothing — the entity only sees what the circle puts in its context window. All three are valid. The spec does not require the loom to be entity-readable, but it does not prohibit it either, and the most capable systems will make use of it.

When the loom is exposed, the entity's relationship to its own history changes. Instead of passively receiving whatever the circle puts in its prompt, the entity actively explores its past through code — summarizing old turns, expanding folded sections, comparing its current approach to earlier attempts, inspecting the results of sibling threads. These are not special introspection channels built into the harness. They are ordinary code execution, using ordinary gates and sandbox primitives, operating on the loom as data.

The decisions the entity makes about how to use its history show up in the trace, flow into the loom, and feed back into training. This is why thin harnesses beat smart harnesses: when the entity manages its own context through code, that intelligence compounds through training. When the harness manages context through built-in logic, that intelligence helps now but does not train into the next generation.

> **LOOM-11**: The loom MAY be exposed as a readable object within the circle's sandbox. When exposed, the entity accesses its own history through code execution, not through special observation channels.

---

## Chapter 7: Production

An entity that works in a demo and an entity that works in production are separated by a set of problems that are boring to describe and fatal to ignore. Context windows fill up. API calls fail. Tokens cost money. Protocols must be spoken correctly. None of this changes the vocabulary — every concept from the previous six chapters applies unchanged. What changes is the operational discipline required to keep the loop running reliably, at scale, over time.

This chapter is shorter than the others, and intentionally so. The conceptual ideas — ephemeral gates, dependency injection — follow directly from the circle model. The infrastructure rules — protocols, retries, token tracking — vary in implementation. What matters here is the contract, not the mechanism.

### 7.1 Context management in production

For context management strategies including folding and compaction, see §6.8. The rules below govern production behavior.

> **PROD-4**: Folding MUST be triggered automatically when context approaches the crystal's limit. Implementations SHOULD trigger folding when context exceeds 80% of the crystal's advertised window (see §6.8 for the rationale). Implementations that use a different threshold MUST document it.

### 7.2 Ephemeral gates

Some gate results are large and useful for exactly one turn — a full webpage, a large file, a database dump. The entity reads the content, extracts what it needs, and moves on. Keeping the full observation in the working context wastes the crystal's window on content that has already been consumed.

An ephemeral gate solves this. Its observation is replaced with a compact reference after the entity's next turn. The full content is stored in the loom — the observation is never lost — but it is removed from the entity's working context. If the entity needs the content again, it calls the gate again.

> **PROD-5**: If ephemeral gates are supported, the full observation MUST still be stored in the loom. Only the working context is trimmed.

This is an optimization, not a requirement. Implementations MAY support ephemeral gates.

### 7.3 Dependency injection

This was introduced in §4.3 and is worth restating here because production is where it becomes critical. Gates close over environment state. A `read` gate knows its filesystem root. A `call_entity` gate holds a reference to the crystal it will use for child entities. A `fetch` gate may carry timeout configuration or authentication headers. These dependencies are injected when the circle is constructed, not when the entity invokes the gate.

```
// Pseudocode: configuring gate dependencies
circle = Circle({
  gates: [
    read.with({ root: "/data" }),
    fetch.with({ timeout: 5000 }),
    call_entity.with({ crystal: child_crystal, max_depth: 2 })
  ],
  wards: [max_turns(100)]
})
```

The entity calls `read("data.json")` without knowing or caring where the filesystem root is. The gate knows. The circle was prepared before the entity appeared. This is dependency injection applied to the boundary between the entity and the world — the entity describes what it wants, the gate resolves how to get it, and the configuration was fixed at construction time.

Implementations SHOULD provide a dependency injection mechanism for gates. CIRCLE-10 already requires that gate dependencies be configured at circle construction time. In practice, this means gates are partially applied functions: the host binds the dependencies, and the entity supplies the arguments.

### 7.4 Infrastructure rules

The remaining production concerns — protocols, retries, token tracking, streaming — are stated as rules with minimal commentary. The implementations vary. The contracts do not.

> **PROD-1**: Protocol adapters MUST NOT alter the entity's behavior. The same cantrip MUST produce the same behavior regardless of whether it is accessed via CLI, HTTP, or ACP.

> **PROD-2**: Retry logic MUST be transparent to the entity. A retried crystal query MUST appear as a single turn, not multiple turns. Implementations SHOULD retry rate limits (429) and server errors (5xx) with exponential backoff starting at 1 second, up to a maximum of 3 retries. Client errors (4xx except 429) MUST NOT be retried.

> **PROD-3**: Token usage MUST be tracked per-turn and cumulatively per-entity.

Token counts are stored per-turn in the loom (LOOM-9) and accumulated across the entity's lifetime. They are how you track cost, detect context growth, and trigger folding. Every turn has a price. The loom records it.

Implementations SHOULD emit streaming events as they occur — reasoning traces, text content, gate invocations, results, token usage. Streaming is an observation channel, not a control channel. Events report what the loop is doing but do not affect its execution.

---

## Glossary

Every term in this document was defined in context as it appeared. This table is for quick reference when you need to look one up.

| # | Term | Common alias | Definition |
|---|------|-------------|-----------|
| 1 | **Crystal** | model | The model. Stateless: messages in, response out. |
| 2 | **Call** | config, conditioning | Immutable identity: system prompt + hyperparameters. What the crystal *is*. |
| 3 | **Gate** | tool, function | Host function that crosses the circle's boundary. |
| 4 | **Ward** | constraint, restriction | Subtractive restriction on the action space. |
| 5 | **Circle** | environment, sandbox | The environment: medium + gates + wards. The medium is the substrate the entity works *in*. |
| 6 | **Intent** | task, goal | The goal. What the entity is trying to achieve. |
| 7 | **Cantrip** | agent config | The recipe: crystal + call + circle. A value, not a process. |
| 8 | **Entity** | agent instance | What emerges when you invoke a cantrip. The living instance. Persists across turns when invoked; discarded after one run when cast. |
| 9 | **Turn** | step | One cycle: entity acts, circle responds, state accumulates. |
| 10 | **Thread** | trajectory, trace | One root-to-leaf path through the loom. A trajectory. |
| 11 | **Loom** | execution tree, replay buffer | The tree of all turns across all runs. Append-only. |

The eleven terms have an internal structure worth noticing. Three are primaries: crystal, call, circle. One is emergent: the entity, which appears when the three primaries are in relationship. The rest pair naturally: gate and ward, intent and thread, turn and loom. The cantrip is the manifest whole that contains all of them. The medium is the circle's substrate — not a twelfth term, but the inside of the fifth. This structure is not accidental — it reflects which concepts are fundamental, which are derived, and how they relate to each other.

## Conformance

An implementation is conformant if it satisfies three conditions:

1. It implements all eleven terms as described
2. It passes the test suite (`tests.yaml`)
3. Every behavioral rule (LOOP-*, CANTRIP-*, INTENT-*, ENTITY-*, CRYSTAL-*, CALL-*, CIRCLE-*, WARD-*, COMP-*, LOOM-*, PROD-*) is satisfied

Implementations MAY extend the spec with additional features as long as the core behavioral rules are preserved. The vocabulary is fixed. What you build on top of it is yours.

The reference implementation is TypeScript/Bun. It is one valid manifestation. The spec is the source of truth.
