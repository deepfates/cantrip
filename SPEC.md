# Cantrip Specification

> *"Neither science nor sorcery have defeated Goliath. Perhaps a combination of the two will be more effective. The cantrips have been spoken. The patterns of force are aligned. Now it is up to your machine, Xanatos."*
>
> — Gargoyles: Reawakening (1995)

**Version**: 0.1.0-draft
**Status**: Draft — behavioral rules for implementation

## Introduction

A cantrip is a small chant. A loop of language.

A language model takes text in and gives text back. You send it a prompt, it returns a completion. One pass — no memory, no consequences, no relationship between what it says and what happens next. This is how most people encounter these systems: you ask a question, you get an answer, you close the tab.

To make it do things, you close the loop. You take the model's output, run it as code in some kind of environment — a sandbox, a REPL, a browser — and feed the result back as input. Now it can act, observe, and act again. Now what it writes has consequences it can perceive. The environment pushes back: code runs or crashes, files exist or don't, tests pass or fail. The model sees that pushback and adjusts. Turn by turn, it accumulates experience. It gets smarter about the task. It starts doing things its designers never specifically enumerated, because the action space is a programming language and programming languages are compositional.

This is call and response. You draw a circle, you speak into it, something answers. The answer changes what you say next. The repetition is the mechanism — each turn through the loop brings the model closer to the task or reveals why the task is harder than it looked. The loop continues until the work is done or a limit is reached.

This document describes the parts of that loop — what they are, what they're called, how they compose, and what you can build with them. There are eleven terms. Three are fundamental: the **crystal** (the model), the **call** (the invocation that shapes it), and the **circle** (the environment it acts in). Everything else is what happens when you put those three together and let the loop run.

Cantrip's vocabulary describes hierarchical agent architectures naturally — from a chat interface to a code-executing RLM (Recursive Language Model — the pattern where data lives in the environment as program state and the entity explores it through code, rather than cramming context into the prompt) to a multi-agent system where parent entities delegate to children. The same eleven terms apply across this range. Only the circle's design changes. A chat window where you talk to a model is a cantrip with a human circle. A tool-calling agent that invokes JSON functions is a cantrip whose action space is just its gates. A code circle — where the entity writes and runs arbitrary programs in a sandbox — is the most expressive case, the largest action space, and gets the most coverage in this document. Peer-to-peer and non-tree topologies are possible extensions but not the focus here.

The same pattern works at every scale. The simplest cantrip is a crystal in a loop with one gate (`done`) and no wards beyond a turn limit — a model that can try things and say when it's finished. The most complex is a tree of entities with recursive composition, folding, and a loom feeding comparative reinforcement learning. Both are described by the same eleven terms; you configure them differently, not rename them. You add components — more gates, more wards, richer circles — but never a twelfth concept.

The spec describes behavior, not technology. It says "the circle must provide sandboxed code execution" — not "use QuickJS." It says "the crystal takes messages and returns a response" — not "use the Anthropic SDK." Any implementation that passes the accompanying test suite (`tests.yaml`) is a valid cantrip. Terms are defined in context as they appear; see the Glossary at the end for a quick reference.

---

## Chapter 1: The Loop

The loop is the foundation. Everything else in this spec — every term, every rule, every architectural decision — exists to give structure to a model acting in a loop with an environment.

### 1.1 The turn

Each cycle through the loop is a turn. A turn has two halves. First, the entity — the running instance of the model inside the loop — produces an **utterance**: text that may contain executable code or structured calls to the environment. Then the **circle** — the environment — executes what the entity wrote and produces an **observation**: a single composite object containing an ordered list of results — one entry per gate call, plus sandbox output if applicable. The observation feeds into the next turn as one unit. State accumulates.

> **LOOP-1**: The loop MUST alternate between entity utterances and circle observations. Two consecutive entity utterances without an intervening observation MUST NOT occur.

This strict alternation is what makes the loop a loop and not a monologue. The entity acts, the world responds, the entity acts again with the world's response in hand. Each turn is a potential learning moment — the entity sees what its code actually did, not what it hoped it would do.

The recipe that defines the loop — which model to use, how to configure it, what environment to place it in — is called a **cantrip**. The goal the entity is pursuing is called an **intent**. These concepts are developed fully in later chapters. For now, what matters is the cycle: act, observe, repeat.

### 1.2 What the entity perceives

On every turn, the entity needs to know two things: what it's supposed to do, and what has happened so far. The **call** — the immutable configuration that shapes the model's behavior — and the **intent** — the goal — are always present. They are the entity's fixed orientation.

Everything beyond that is mediated by the circle. The circle determines what the entity perceives each turn. In the simplest design, the circle presents the full history of prior turns as a growing message list — every utterance, every observation, appended in order. This is how most agent systems work today. It is one valid approach, and the most expensive one. In a code circle, the entity can access state through code instead: reading variables, querying data structures, inspecting files that persist between turns. The growing message list and program-state access are both valid circle designs. What the entity sees is the circle's decision.

> **LOOP-5**: The entity MUST receive the call and the intent on every turn. How prior turns are presented — as a message history, as program state, or as a combination — is determined by the circle's design. The circle mediates what the entity perceives.

This rule is deliberately permissive. A circle that stuffs every prior turn into the prompt is conformant. A circle that stores prior turns as program state the entity accesses through code is also conformant. The call and intent are the only things the spec requires on every iteration. Everything else is a design choice, and the circle makes it.

### 1.3 Termination and truncation

The loop ends in exactly one of two ways, and the difference matters.

**Terminated** means the entity called the `done` gate — a special exit point in the environment that signals "I believe the task is complete." The entity chose to stop. The final state is terminal: the entity had the opportunity to finish its work and took it.

**Truncated** means a **ward** cut the entity off. A ward is a restriction on the loop — a maximum number of turns, a timeout, a resource limit. The environment chose to stop. The final state is not terminal: the entity was interrupted, not finished. It might have had more to do.

> **LOOP-2**: The loop MUST terminate. Every cantrip MUST have at least one termination condition (a `done` gate, or text-only response when `require_done` is false) AND at least one truncation condition (a max turns ward).

Both conditions are required because they serve different purposes. The `done` gate is how the entity signals success. The max turns ward is the safety net that prevents infinite loops. A cantrip that can run forever is invalid. A cantrip with no way to signal completion is useless.

> **LOOP-3**: When the `done` gate is called, the loop MUST stop after processing that gate. Any remaining gate calls in the same utterance MAY be skipped.

> **LOOP-4**: When a ward triggers truncation, the loop MUST stop. The implementation SHOULD generate a summary of what was accomplished before the entity was cut off.

There is a third case. If the entity produces a text-only response — no code, no gate calls, just words — the loop needs a policy. The cantrip's `require_done` flag controls the answer. When `require_done` is false (the default), a text-only response is a natural stopping point: the entity said what it had to say and made no further moves. When `require_done` is true, only an explicit `done` gate call terminates the loop — text-only responses are treated as turns that happen not to use gates, and the loop continues.

> **LOOP-6**: If `require_done` is false (default) and the entity produces a text-only response (no gate calls), the loop MUST treat that as implicit termination. If `require_done` is true, a text-only response MUST NOT terminate the loop — only a `done` gate call terminates.

The distinction between termination and truncation matters beyond the loop itself. A terminated thread is a completed episode — training data with a natural endpoint. A truncated thread is an interrupted episode — the entity's final state shouldn't be treated as a conclusion because it wasn't one. Implementations MUST record which occurred.

### 1.4 The cantrip, the intent, and the entity

Three terms appear throughout this chapter that get their full treatment later. Here is what they mean and where to find the details.

A **cantrip** is the recipe that produces the loop. It binds a crystal to a circle through a call — which model, which configuration, which environment. A cantrip is a value, not a running process. You write it once and cast it many times.

> **CANTRIP-1**: A cantrip MUST contain a crystal, a call, and a circle. Missing any of these is invalid.

> **CANTRIP-2**: A cantrip is a value. It MUST be reusable — casting it multiple times on different intents MUST produce independent entities.

> **CANTRIP-3**: Constructing a cantrip MUST validate that the circle has a `done` gate (CIRCLE-1) and at least one truncation ward (CIRCLE-2).

An **intent** is the reason the loop runs — the goal, the task, the thing the entity is trying to achieve. Same cantrip, different intent, different episode. The intent is what varies between runs.

> **INTENT-1**: The intent MUST be provided when casting a cantrip. A cantrip cannot be cast without an intent.

> **INTENT-2**: The intent MUST appear as the first user message in the entity's context, after the system prompt (if any).

> **INTENT-3**: The intent is immutable for the lifetime of the entity. The entity cannot change its own intent.

And the **entity** is what appears when you cast a cantrip on an intent and the loop starts running.

Watch what happens after a few turns.

The crystal's output on turn twelve doesn't look like its output on turn one. It's referencing variables it created on turn four. It's working around an error it hit on turn seven. It's pursuing a strategy that emerged from something it noticed on turn nine — a pattern in the data that nobody told it to look for. The call didn't ask for this strategy. The circle didn't suggest it. It appeared in the space between them, born from the accumulation of action and observation.

This is the entity. Not a thing you built — a thing that arose. The crystal is the same crystal it was before the loop started. The call hasn't changed. The circle is just an environment, doing what environments do. But the process running through all three of them has developed something that looks uncomfortably like perspective. It has context. It has momentum. It has preferences shaped by what it's tried and what worked.

You didn't design the entity. You designed the crystal, the call, and the circle. The entity is what happened when you put them together and let the loop run.

It will exist for as long as the loop runs. When the loop stops — task complete, budget exhausted, ward triggered — the entity is gone. The crystal remains, unchanged. The circle can be wiped or preserved. But the entity, that particular accumulation of context and strategy and in-context learning, is over. It lived in the loop and the loop is done.

Unless you recorded it. But that's a later chapter.

> **ENTITY-1**: An entity MUST be produced by casting a cantrip on an intent. There is no other way to create an entity.

> **ENTITY-2**: Each entity MUST have a unique ID.

> **ENTITY-3**: An entity's state MUST grow monotonically within a thread (modulo folding, which is a view transformation, not deletion — see Chapter 6).

> **ENTITY-4**: When an entity terminates or is truncated, its thread persists in the loom. The entity ceases but its record endures.

The crystal, the call, and the circle each have their own chapters. The entity does not, because the entity is not a component you configure. It is what emerges from the components you did configure, once the loop begins.

### 1.5 The RL correspondence

If you know reinforcement learning, here is how the vocabulary maps. If you do not, skip this section — the spec teaches everything you need without it.

The mapping is structural, not formal. Cantrip's terms parallel RL concepts in their relationships — the crystal is to cantrip what the policy is to RL, the circle is what the environment is to RL. These are not mathematical equivalences you can plug into RL equations. They are structural parallels that help you reason about the system.

| RL concept | Cantrip equivalent | Notes |
|-----------|-------------------|-------|
| Policy | Crystal + Call | Frozen weights conditioned by immutable prompt and gate definitions |
| Goal specification | Intent | The desire that shapes which actions are good |
| State s | Circle state | Accessed through gates. The message list is one circle design, not the default |
| Action a | Code the entity writes | A = (L + G) minus W |
| Observation o | Gate return values + sandbox output | Rich, unstructured |
| Reward r | Implicit or explicit | Implicit: gate success/failure. Explicit: verifier scores. Comparative: ranking threads of the same intent |
| Terminated | `done` gate called | Entity chose to stop |
| Truncated | Ward triggered | Environment chose to stop |
| Trajectory | Thread | One root-to-leaf path through the loom |
| Episode | Entity lifetime | First turn to termination/truncation |
| Replay buffer | Loom | Richer: the tree structure provides the trajectory data comparative RL methods need |
| Environment reset | New entity, clean circle | Forking is NOT a reset — it continues from prior state |

The loom's relationship to modern RL methods is developed fully in Chapter 6.

---

## Chapter 2: The Crystal

The crystal is the model. It takes messages and returns a response. That is the whole interface.

A crystal does not act on its own. It has no memory between invocations, no persistent state, no ongoing relationship with the world. You send it a list of messages — system instructions, prior conversation, whatever context you have assembled — and it sends back text, or structured calls to gates, or both. Then it is done. The next time you invoke it, you must send everything again. The crystal does not remember that there was a last time.

> **CRYSTAL-1**: A crystal MUST be stateless. Given the same messages and tool definitions, it SHOULD produce similar output (modulo sampling). It MUST NOT maintain internal state between invocations.

This statelessness is not a limitation of current technology. It is the contract. The crystal is a function: messages in, response out. Everything that makes an entity seem to learn and adapt across turns — everything described in Chapter 1 — comes from the loop feeding the crystal's own prior output back as input. The crystal itself is the same on every invocation. The context around it changes.

### 2.1 The crystal contract

A crystal is anything that satisfies this interface:

```
crystal.invoke(messages: Message[], tools?: ToolDefinition[], tool_choice?: ToolChoice) -> Response
```

The inputs:
- `messages` is an ordered list of messages (system, user, assistant, tool). The crystal sees the full conversation as the caller has assembled it.
- `tools` is an optional list of gate definitions, expressed as JSON Schema. These describe what the crystal can ask the environment to do.
- `tool_choice` controls whether the crystal must use gates ("required"), may use them ("auto"), or must not ("none").

The response contains:
- `content`: text output (may be null if the crystal only made gate calls)
- `tool_calls`: an optional list of gate invocations, each with an ID, gate name, and JSON arguments
- `usage`: token counts (prompt, completion, cached)
- `thinking`: optional reasoning trace (for models that support extended thinking)

Every response must include at least one of these first two fields. A response with neither text nor gate calls is not a response — the crystal produced nothing.

> **CRYSTAL-2**: A crystal MUST accept messages up to its provider's context limit. When input exceeds that limit, the crystal MUST return a structured error (not silently truncate). The caller — circle or harness — is responsible for staying within limits via folding (§6.8).

> **CRYSTAL-3**: A crystal MUST return at least one of `content` or `tool_calls`. A response with neither is invalid.

> **CRYSTAL-4**: Each `tool_call` MUST include a unique ID, the gate name, and arguments as a JSON string.

The unique ID matters because gate results must be matched back to the calls that produced them. Without it, the crystal cannot distinguish which observation came from which request.

> **CRYSTAL-5**: If `tool_choice` is "required", the crystal MUST return at least one tool call. If the provider doesn't support forcing tool use, the implementation MUST simulate it (e.g., by re-prompting).

### 2.2 The swap

Same circle, same call, different crystal — different behavior, same loop.

This is the move that reveals what the crystal is and what it is not. You take a working cantrip — a system prompt, an environment with gates and wards, an intent — and you replace the crystal. The circle does not change. The call does not change. The gates are the same, the wards are the same, the intent is the same. But the entity that appears behaves differently. It reasons differently, makes different mistakes, pursues different strategies, writes different code.

The crystal is the one component you swap to change how the entity thinks without changing what it can do or where it acts. Everything else in the system — the environment, the conditioning, the available actions — stays fixed. Only the intelligence varies. This is what it means for the crystal to be a separable component of the loop, and it is the reason the spec treats it as one.

### 2.3 Provider implementations

The spec requires support for at least these provider families:
- **Anthropic** (Claude models)
- **OpenAI** (GPT models)
- **Google** (Gemini models)
- **OpenRouter** (proxy to many providers)
- **Local** (Ollama, vLLM, any OpenAI-compatible endpoint)

Each provider has its own API, its own authentication, its own way of representing messages and tool calls. The provider implementation translates between the crystal contract above and the provider's native format. From the loop's perspective, every crystal looks the same.

> **CRYSTAL-6**: Provider implementations MUST normalize responses to the common crystal contract. Provider-specific fields (stop_reason, model ID, etc.) MAY be preserved as metadata but MUST NOT be required by consumers.

This normalization is what makes the swap possible. If consumers depended on provider-specific fields, changing the crystal would break the loop. The contract is the boundary. Everything behind it is the provider's business.

---

## Chapter 3: The Call

The call is everything that shapes the crystal's behavior before any intent arrives. It is small, it is fixed, and it does not change for the lifetime of the cantrip.

> **CALL-1**: The call MUST be set at cantrip construction time and MUST NOT change afterward.

### 3.1 What the call contains

The call is the union of three things:

1. **System prompt** — persona, behavioral directives, domain knowledge. The text that tells the crystal who it is and how it should behave.
2. **Hyperparameters** — temperature, top_p, max_tokens, stop sequences, sampling configuration. The knobs that control how the crystal generates.
3. **Gate definitions** — the circle's interface, rendered as text for the crystal to perceive.

The third element deserves attention. Gate definitions are text. When you register gates in a circle and the call is assembled, those gate definitions are rendered into structured text — typically JSON Schema or a similar format — and included in the prompt the crystal sees. The crystal does not perceive "tools" as a separate mechanism from the rest of its input. It perceives text that describes what it can do, formatted in a way it has been trained to recognize and act on. This is true of every major provider: tool definitions are rendered into the prompt as structured text before the crystal sees them.

The call, then, sits between the crystal and the circle. It is how the circle presents itself to the crystal. The gate definitions are part of the call because the crystal perceives its circle through the call — it has no other channel. What the call describes, the crystal can attempt. What the call omits, the crystal does not know exists.

> **CALL-3**: Gate definitions MUST be derived from the circle's registered gates. Adding or removing a gate changes the call (which means creating a new cantrip, not mutating this one).

This follows from immutability. If you add a gate to the circle, the crystal needs to know about it, which means the gate definitions in the call must change, which means you have a different call, which means you have a different cantrip. The binding between circle and call is tight.

### 3.2 Immutability and identity

The call is fixed. You can create a new cantrip with a different call, but you cannot mutate the call of an existing one. This gives you two clean axes of variation:

Same crystal + different call = different entity behavior. Change the system prompt, and the same model reasons differently about the same task. Change the temperature, and the same model explores differently. Change the available gates, and the same model acts in a different world.

Same crystal + same call + different intent = different episode. The cantrip is the same recipe. The intent is what varies between runs.

> **CALL-2**: If a system prompt is provided, it MUST be the first message in every context sent to the crystal. It MUST be present in every invocation, unchanged.

The system prompt anchors the crystal's behavior across every turn of the loop. It is the one piece of context that never moves, never compresses, never gets folded away. The entity always knows who it is.

### 3.3 What the call is not

The call is small and fixed. The circle holds the state. The entity explores it through code.

Dynamic context — retrieved documents, injected state, programmatic insertions that change per turn — is not part of the call. These are circle state, accessed through gates. A cantrip that processes a thousand documents does not stuff them into the system prompt. It places them in the circle as data the entity can read, query, and navigate through code. The call tells the entity what it can do. The circle contains what it works with.

This is the core architectural insight: context belongs in the environment, not in the prompt. The prompt is small, fixed conditioning. The environment is large, rich, and explorable. When the entity needs information, it reaches for it through a gate — reading a file, querying a data structure, inspecting a variable that persists in the sandbox between turns. The call does not grow. The circle does.

### 3.4 The call in the loom

> **CALL-4**: The call MUST be stored in the loom as the root context. Every thread starts from the same call.

When you fork a thread — branching from an earlier turn to explore a different path — both branches share the same call. They diverge in experience but not in conditioning. The entity always retains its full identity.

> **CALL-5**: Folding (context compression) MUST NOT alter the call. The entity always retains its full conditioning. Only the trajectory (turns) may be folded.

When context grows too large and older turns must be compressed to fit the crystal's window, the call is exempt. The system prompt, the hyperparameters, the gate definitions — these survive folding intact. The entity may lose detailed memory of what it did on turn three, but it never loses its sense of who it is and what it can do.

---

## Chapter 4: The Circle

The circle is the environment where the entity acts.

### 4.1 What a circle is

A circle is anything that receives the entity's output and returns an observation. Circles exist on a spectrum of expressiveness, and the cantrip vocabulary applies across that spectrum.

The simplest circle is a human circle. You type something to ChatGPT, the model responds, your next message is shaped by what it said. You are the environment. Your judgment is the pushback. The action space is just conversation — there are no gates beyond the implicit exchange, no sandbox, no persistent state. The formula collapses: A is whatever the model can say.

A tool-calling circle adds gates. The entity invokes JSON functions — `read`, `fetch`, `search` — and receives structured results. There is no sandbox, no language primitives the entity can compose on its own. The action space is just the gate set: A = G minus W. This is how most agent systems work today. It is valid and common.

A code circle gives the entity a full execution context — a sandbox where it can write and run arbitrary programs, with gates to the outside world and wards that constrain what is allowed. The entity writes code. The sandbox executes it. The result comes back as an observation. Variables persist between turns. Errors are visible. The ground pushes back with truth, not opinion. The action space is the full formula: A = (L + G) minus W. The entity can combine language primitives and gates in ways nobody enumerated in advance — loops that call gates conditionally, variables that store gate results for later turns, data pipelines composed on the fly. This compositionality is what makes code circles the most expressive case.

These are points on a spectrum, not categories with hard boundaries. A tool-calling agent that generates JSON is closer to a code circle than a chat window is, but it lacks the compositionality of a real sandbox. A code circle with no gates beyond `done` is more constrained than a tool-calling agent with twenty gates, but its action space is still richer because it has a programming language. What varies is the circle's design. What stays the same is the vocabulary: crystal, call, circle, gate, ward, entity, turn, thread, loom. The rest of this chapter focuses on code circles — the most expressive case, where the most interesting design questions arise — but the concepts apply everywhere.

### 4.2 What the entity can do

The entity's capabilities in a code circle are described by a formula:

```
A = (L + G) − W
```

**L** is the language. Whatever the sandbox provides — builtins, math, strings, control flow, data structures, standard library. These are the primitives the entity can compose without crossing any boundary.

**G** is the set of registered gates. Gates are host functions that cross the circle's boundary into the outside world: reading files, making HTTP requests, spawning child entities. They are the entity's exits from the sandbox.

**W** is the set of wards. Wards are restrictions that remove or constrain elements of L and G. A ward might remove a gate entirely, restrict a gate's reach, cap the number of turns, or limit resource consumption.

The action space A is what remains after wards have carved away what is forbidden. The entity starts with the full surface of the language plus every registered gate. Wards subtract from that surface. What is left is what the entity can do.

This is not a metaphor. It is how the system actually works. And the formula reveals something important: the action space is a programming language. The entity can combine primitives and gates in ways nobody enumerated in advance. It can write a loop that calls a gate conditionally. It can store a gate's result in a variable and use it three turns later. It can compose gates with language primitives in any way the language allows. This compositionality is what separates a code circle from a tool-calling interface.

> **CIRCLE-1**: A circle MUST provide at least the `done` gate.

The `done` gate is the minimum. Without it, the entity has no way to signal that it believes the task is complete. Every other gate is optional and domain-specific.

> **CIRCLE-8**: The `done` gate MUST accept at least one argument: the answer/result. When `done` is called, the loop terminates with that result.

### 4.3 Gates

Gates are crossing points through the circle's boundary. Inside the sandbox, the entity operates freely within the language. Gates are how effects reach the outside world — and how outside information reaches the entity.

Common gates:
- `done(answer)` — signal task completion, return the answer
- `call_agent(intent, config?)` — cast a child cantrip on a derived intent
- `call_agent_batch(intents)` — cast multiple child cantrips in parallel
- `read(path)` — read from the filesystem
- `write(path, content)` — write to the filesystem
- `fetch(url)` — HTTP request
- `goto(url)` / `click(selector)` — browser interaction

Each gate closes over environment state. A `read` gate knows its filesystem root. A `call_agent` gate holds a reference to the crystal it will use for child entities. A `fetch` gate may carry timeout configuration or authentication headers. You configure what each gate has access to when you construct the circle — not when the entity invokes the gate.

> **CIRCLE-10**: Gate dependencies (injected resources) MUST be configured at circle construction time, not at gate invocation time.

This is dependency injection for gates. The entity calls `read("data.json")` without knowing or caring where the filesystem root is. The gate knows. The circle was prepared before the entity appeared.

> **CIRCLE-3**: Gate execution MUST be synchronous from the entity's perspective — the entity sends a gate call, the circle executes it, the observation returns before the next turn begins.

The entity never has to wonder whether a gate has finished. It calls a gate, receives the result, and proceeds. The implementation may do asynchronous work behind the scenes, but from the entity's perspective, every gate call is a function that returns a value.

> **CIRCLE-4**: Gate results MUST be returned as observations in the context. The entity MUST be able to see what its gate calls returned.

> **CIRCLE-5**: If a gate call fails (throws an error), the error MUST be returned as an observation, not swallowed. The entity MUST see its failures.

Swallowing errors is a common implementation mistake that silently cripples the entity. If a file does not exist, the entity needs to see the error so it can try a different path. If a network request times out, the entity needs to know so it can retry or adjust its strategy. Errors are observations. They carry information.

> **CIRCLE-7**: If multiple gate calls appear in a single utterance, the circle MUST execute them in order and return each result as an entry within that turn's single composite observation. The observation is one object per turn (preserving LOOP-1's strict alternation), with an ordered list of per-gate results inside it. Implementations MAY execute independent gate calls in parallel.

### 4.4 Wards

Wards are the other half of the circle's design. Where gates expand the entity's reach beyond the sandbox, wards contract it. They are subtractive — they remove or constrain elements of the full action space, not permissions granted from nothing.

A ward that removes a gate shrinks G: "this circle has no network access" means `fetch` is not registered. A ward that restricts a gate's reach narrows what the gate can do: "read only from /data" means the `read` gate rejects paths outside that directory. A ward that caps turns bounds the episode: "max 200 turns" means the loop is cut off if the entity has not called `done` by then. A ward that limits resources prevents runaway consumption: "max 1M tokens," "timeout after 5 minutes."

> **CIRCLE-2**: A circle MUST have at least one ward that guarantees termination (max turns, timeout, or similar). A cantrip that can run forever is invalid.

This is the safety net. The `done` gate is how the entity chooses to stop. A termination ward is how the environment forces a stop when the entity does not. Both are required — one is the mechanism of completion, the other is the guarantee against infinite loops.

> **CIRCLE-6**: Wards MUST be enforced by the circle, not by the entity. The entity cannot bypass a ward. Wards are environmental constraints.

This is the critical distinction. A ward is not a polite request. It is not an instruction in the system prompt that the entity might ignore. It is a structural property of the environment. If `fetch` is not registered, the entity cannot make HTTP requests no matter what it writes. If the turn limit is 200, turn 201 does not happen. The entity cannot reason its way around a ward because the ward operates outside the entity's control.

The philosophical orientation here follows the Bitter Lesson: abstractions that constrain the action space fight against model capability. The entity should start with the fullest possible action space. Then you ward off what is dangerous. You do not build up from nothing — you carve down from everything.

### 4.5 Tool-calling circles

When the crystal uses structured tool calls — JSON function invocations rather than code in a sandbox — the action space simplifies to A = G minus W, as described in §4.1. The entity can only invoke gates by name with JSON arguments. There are no language primitives to compose with.

Implementations MUST support tool-calling circles. Implementations SHOULD support code circles.

### 4.6 Circle-mediated perception

The circle does more than execute code. It determines what the entity perceives.

The call and the intent are always present — they are the entity's fixed orientation, delivered on every turn (as established in LOOP-5). Everything beyond that is the circle's decision. The circle controls how prior experience is presented to the entity, and this is a design choice with real consequences.

The simplest approach is the one most agent systems use today: stuff the full history of prior turns into the prompt as a growing message list. Every utterance and every observation, appended in order, visible to the crystal on every invocation. This works. It is also the most expensive design, because the prompt grows with every turn, and the crystal re-reads everything it has already seen.

In a code circle, there is another option. The entity can access prior state through code — reading variables that persist in the sandbox, querying data structures it built on earlier turns, inspecting files it wrote to disk. The message history can be slim or even absent, because the entity's knowledge lives in the environment as program state rather than in the prompt as text. This is the RLM pattern in action — the principle from §3.3 that context belongs in the environment, not in the prompt.

Both designs are valid. A circle that presents full message history is conformant. A circle that stores state as program variables the entity accesses through code is also conformant. The spec does not mandate one approach over the other. What matters is that the call and intent are always present, and that the entity can perceive the consequences of its prior actions — however the circle chooses to make those consequences available.

### 4.7 Circle state

The circle maintains state between turns. This state comes in two forms.

**Sandbox state** is what lives inside the execution context — variables, data structures, intermediate results that the entity created through code and that persist across turns within the same entity.

> **CIRCLE-9**: In a code circle, sandbox state MUST persist across turns within the same entity. A variable set in turn 3 MUST be readable in turn 4.

Without this guarantee, the entity cannot build on its own work. Each turn would start from scratch, and the entity would have to re-derive everything it knew from the message history alone. Persistent sandbox state is what makes a code circle a code circle — the entity accumulates not just conversation but computation.

**External state** is what lives outside the sandbox but is accessible through gates — the filesystem, a database, browser DOM, whatever resources the gates have been configured to reach. External state may be shared across entities or persist beyond a single entity's lifetime. Sandbox state is private to the entity and dies when the entity terminates.

### 4.8 Security

Security in the circle model is a question of warding.

The canonical threat is the lethal trifecta: a circle that has access to private data, processes untrusted content, and can communicate externally. Any two of these together are manageable. All three in the same circle create a path for data exfiltration — untrusted content instructs the entity to read private data and send it out through a network gate.

The defense is subtractive. Remove one leg of the trifecta by warding off the relevant gate. A circle that processes untrusted content and reads private data but cannot make network requests is safe against exfiltration. A circle that has network access and reads private data but never processes untrusted input is also safe. Alternatively, isolate capabilities across separate circles — one circle handles untrusted content with network access but no private data, another handles private data with no network access.

Security is not a feature you bolt on. It is what you carve away. Drawing good circles — choosing which gates belong together and which must be separated — is the practitioner's art.

---

## Chapter 5: Composition

In most agent frameworks, delegation is a special mechanism — a workflow node, a handoff protocol, a message passed through an orchestrator. In a code circle, delegation is a function call. The entity writes `call_agent({ intent: "summarize this document" })` and a child entity appears in its own circle, pursues that sub-intent, and returns a result. The parent blocks until the child finishes. From the parent's perspective, it called a function and got a value back. From the loom's perspective, a subtree just grew.

This matters because the entity writes code, and code composes. The entity does not delegate through a configuration file or a workflow graph. It delegates inside loops, behind conditionals, as part of programs it writes on the fly. Composition through gates is composition through code, which means the entity can invent delegation patterns its designers never enumerated — recursive intelligence, not an API call.

This is how intent spawns sub-intents. The parent entity is pursuing some goal — "fix my application" — and discovers, mid-task, that it needs to understand a database schema, refactor an authentication module, and rewrite a set of tests. Each of these is a desire born from the parent's desire. The parent's intent does not change — it is still trying to fix the application. But the work of fixing the application generates child intents, and `call_agent` is the gate through which they are pursued.

### 5.1 The `call_agent` gate

```
result = call_agent({
  intent: "Summarize this document",
  context?: any,         // data injected into child's circle
  system_prompt?: string, // child's call (defaults to parent's)
  max_depth?: number      // recursion limit ward
})
```

The child entity gets its own circle, its own context, its own turn sequence. It does not inherit the parent's conversation history — it starts fresh, with only the sub-intent and whatever data the parent passes through the `context` field.

> **COMP-4**: A child entity MUST have its own independent context (message history). The child does not inherit the parent's conversation history.

The child's circle is carved from the parent's. This is the subtractive principle from Chapter 4 applied to composition: the parent cannot grant gates it does not have. A parent entity with no `fetch` gate cannot give its child network access. The child's circle is always a subset.

> **COMP-1**: A child entity's circle MUST be a subset of the parent's circle. You cannot grant gates the parent doesn't have.

But the child's crystal and call may differ. You might send a cheaper, faster crystal to handle a simple sub-task, or provide a different system prompt that specializes the child for the work at hand. The circle is inherited (subtractively). Everything else can be configured per child.

> **COMP-7**: The child's crystal MAY differ from the parent's crystal (if the `call_agent` config specifies a different one). The child's call MAY differ. Only the circle is inherited (subtractive).

The parent blocks while the child runs. This is synchronous from the parent's perspective — the same contract as any other gate (CIRCLE-3). The child entity lives its entire life within the parent's turn: it appears, acts across however many turns it needs, terminates or is truncated, and the parent receives the result.

> **COMP-2**: `call_agent` MUST block the parent entity until the child completes. The parent receives the child's result as a return value.

If the child fails — throws an error rather than calling `done` — the error comes back as the gate result. The parent sees it as an observation and decides what to do. A child's failure does not kill the parent.

> **COMP-8**: If a child entity fails (throws an error, not `done`), the error MUST be returned to the parent as the gate result. The parent MUST NOT be terminated by a child's failure.

### 5.2 Batch composition

`call_agent_batch` spawns multiple children in parallel:

```
results = call_agent_batch([
  { intent: "Summarize chunk 1", context: chunk1 },
  { intent: "Summarize chunk 2", context: chunk2 },
  { intent: "Summarize chunk 3", context: chunk3 },
])
```

The children execute concurrently. Results are returned as an array in the order they were requested, not in the order the children finish. This gives the parent a predictable interface — `results[0]` always corresponds to the first intent, regardless of which child was fastest.

> **COMP-3**: `call_agent_batch` MUST execute children concurrently. Results MUST be returned in request order, not completion order.

### 5.3 Composition as code

The power of composition in a code circle is that it composes with the language. The entity does not just call `call_agent` once — it calls it inside loops, behind conditionals, as part of data pipelines it writes on the fly. This is the RLM pattern applied to delegation: data lives in the circle as a variable, the entity explores it through code, and sub-entities handle the pieces.

```
// Inside the entity's code (in the sandbox):
const chunks = splitIntoChunks(context.documents, 100);
const summaries = call_agent_batch(
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

Composition is recursive. A child entity has the `call_agent` gate in its circle (inherited from the parent), so it can spawn children of its own. To prevent infinite recursion, every cantrip has a `max_depth` ward.

- Depth 0 means no `call_agent` allowed — the gate is warded off
- Each child's depth limit is the parent's depth minus 1
- Default depth is 1 (the entity can spawn children, but those children cannot spawn their own)

> **COMP-6**: When `max_depth` reaches 0, the `call_agent` and `call_agent_batch` gates MUST be removed from the circle (warded off). Attempts to call them MUST fail with a clear error.

This is warding applied to recursion. The depth limit does not tell the entity to stop delegating — it removes the gate entirely, making delegation structurally impossible at that level.

### 5.5 Composition in the loom

Every child entity's turns are recorded in the same loom as the parent. The child's turns form a subtree, with the child's root turn referencing the parent turn that spawned it.

```
Parent turn 1
Parent turn 2 (calls call_agent)
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

They went into the loom. Every turn — every utterance, every observation, every gate call and its result — was recorded as it happened, appended to a growing tree. One path through that tree is a thread. All threads, across all runs of a cantrip, form the loom.

The loom was accumulating from the first turn of Chapter 1. When the entity emerged and started acting, the loom was already there, writing down everything. When composition spawned child entities in Chapter 5, their turns went into the same loom, branching off the parent's thread as subtrees. The structure described in the last five chapters — the loop, the crystal's responses, the circle's observations, the parent-child relationships of composed entities — is the structure of the loom. The loom is what all of it produces.

### 6.1 Turns as nodes

Each turn is stored as a record:

```
Turn {
  id: string             // unique identifier
  parent_id: string?     // null for root turns
  cantrip_id: string     // which cantrip produced this turn
  entity_id: string      // which entity was acting
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

The metadata is not optional bookkeeping. Token counts are how you track cost. Timing is how you find bottlenecks. The reward slot — empty by default — is how the loom becomes training data. Every field on the turn record exists because something downstream needs it.

### 6.2 Threads

A thread is a path through the turn tree from root to leaf. Threads are implicit — they emerge from the parent references on turns. You do not store threads separately. You store turns with parent pointers, and a thread is any root-to-leaf path you can walk.

A thread has exactly one of these terminal states:
- **Terminated**: the final turn called `done`
- **Truncated**: a ward stopped the entity
- **Active**: the entity is still running (only during execution)

> **LOOM-7**: The loom MUST record whether each terminal turn was terminated (entity called `done`) or truncated (ward stopped the entity).

The distinction matters beyond bookkeeping. A terminated thread is a completed episode — the entity finished its work, and the final state represents a conclusion. A truncated thread is an interrupted episode — the entity was cut off, and its final state should not be treated as an endpoint because it was not one. Training on the loom must respect this difference: terminated threads have natural endpoints, truncated threads do not.

### 6.3 The loom

The loom is the tree of all turns produced by a cantrip across all its runs. Cast the same cantrip on ten different intents and you get ten threads in one loom. Fork from turn seven of one thread and you get a branch — two threads sharing a common prefix, diverging from the fork point. Compose with `call_agent` and child subtrees grow inside parent threads. The loom holds all of it.

This is the most valuable artifact a cantrip produces. It is:
- **The debugging trace** — walk any thread to see every decision the entity made
- **The entity's memory** — context for forking, folding, and replaying
- **The training data** — each turn is a (context, action, observation) triple, each thread is a trajectory, reward slots are already there
- **The proof of work** — evidence of what the entity did and why

### 6.4 Reward and training data

This is the loom's deepest purpose. Each turn is a (context, action, observation) triple. Each thread is a trajectory. The reward slots are already there. The loom is not merely a replay buffer to be sampled from. It is a training data store — and its tree structure is shaped for the comparative methods that need it most.

The loom stores a reward slot on every turn. What fills it is up to the implementation.

- **Implicit reward** — did the gate succeed? Did the code throw? Gate-level success/failure is a natural per-turn signal.
- **Explicit reward** — a score attached after the fact. A human rates the thread. An automated verifier checks the output. A verifier entity — itself a cantrip — evaluates the work.
- **Shaped reward** — intermediate rewards computed by a scoring function that is part of the circle definition. The rubric is part of the environment.

For in-context learning within a session, implicit reward is enough. The entity sees what worked and what did not in its own context window and adjusts. For training across sessions — reinforcement learning on the loom — you need explicit reward annotation.

Modern LLM-RL methods — GRPO, RLAIF, best-of-N sampling — do not learn from single trajectories in isolation. They learn by comparing multiple trajectories of the same task. GRPO (Group Relative Policy Optimization) generates N completions for the same prompt, ranks them, and uses the relative ranking as the reward signal. No absolute reward model is needed. The comparison is the learning signal.

The loom affords exactly this structure. Fork from the same turn N times — or cast the same cantrip on the same intent N times — and you get N threads that share a common origin but diverge in execution. Rank them by outcome (which thread solved the task? which was most efficient? which produced the cleanest code?) and the ranking becomes a reward signal. The loom's tree structure provides the trajectory data that comparative RL methods need.

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

This is not a feature bolted onto the loom after the fact. It is what the loom's structure naturally affords. A flat log of turns could support single-trajectory training. The tree structure — with forking, branching, and multiple threads from the same origin — supports comparative training. The loom is a training data store shaped for comparative methods, not just a replay buffer. Multi-turn credit assignment remains an active research problem. The loom provides the trajectory structure these methods need; the credit assignment and reward propagation are the responsibility of whatever training infrastructure consumes it.

> **LOOM-10**: The loom MUST support extracting any root-to-leaf path as a thread (trajectory) for export, replay, or training.

The sections that follow describe the loom's structural mechanics — storage, forking, composition, context management — that make this training purpose possible.

### 6.5 Storage

Turns are appended as they happen. The loom is append-only.

> **LOOM-3**: The loom MUST be append-only. Turns MUST NOT be deleted or modified after creation. Reward annotation is the exception — reward MAY be assigned or updated after creation.

The reference storage format is JSONL — one JSON object per line, one turn per line, appended in chronological order. Implementations MAY use other storage backends as long as the append-only semantic is preserved. What matters is that no turn is ever lost, rewritten, or silently dropped. The loom is the ground truth.

### 6.6 Forking

Forking creates a new turn whose parent is an earlier turn in the tree, diverging from the original continuation.

```
// Original thread: turns 1 -> 2 -> 3 -> 4 -> 5
// Fork from turn 3:
// turns 1 -> 2 -> 3 -> 4 -> 5   (original thread)
//                   \-> 6 -> 7   (forked thread)
```

A forked entity starts with the context from the fork point — all turns from root to the fork turn. The original thread is untouched. The new thread grows independently.

> **LOOM-4**: Forking from turn N MUST produce a new entity whose initial context is the path from root to turn N. The original thread MUST be unaffected.

Forking is not an environment reset. The forked entity continues from the accumulated state at the fork point. It has the same context the original entity had at that moment — the same variables in the sandbox, the same history of actions and observations. What differs is the future. The original entity went one way from turn 3. The forked entity goes another. Both paths are recorded. Both threads persist.

This is where the loom's tree structure earns its keep. A flat log could record one thread. A tree records every branch, every alternative path, every "what if we had gone left instead of right." The loom is a map of the roads taken and not taken, and forking is how you explore new roads from old waypoints.

### 6.7 Composition in the loom

When `call_agent` spawns a child entity, the child's turns form a subtree rooted at the parent turn that spawned it. This was described in Chapter 5 from the parent's perspective. From the loom's perspective, it is the same mechanism as forking — a new branch grows from an existing turn — except the branch is a child entity pursuing a sub-intent, and its result flows back into the parent's thread.

> **LOOM-8**: Child entity turns from `call_agent` MUST be stored in the same loom as the parent, with parent references linking them to the spawning turn.

Everything stays in one tree. The parent's thread, the child's subtree, a grandchild's sub-subtree — all recorded in the same loom with parent pointers connecting them. You can walk any path. You can see the full hierarchy of delegation. The loom does not distinguish between "main work" and "delegated work." It records turns, and the structure emerges from their relationships.

### 6.8 Folding and compaction

Context grows. Every turn adds to what the entity has seen and done. Eventually, the accumulated context approaches the crystal's window limit, and something must give.

There are two responses to this pressure, and they are not the same thing.

**Folding** is the deliberate integration of loom history into circle state. Instead of keeping every prior turn in the message list for the crystal to re-read, the entity — or the circle on the entity's behalf — takes the substance of earlier turns and encodes it as state the entity can access through code: variables, data structures, summaries stored in the sandbox. The full turns remain in the loom. The entity's working context shrinks because the knowledge now lives in the environment rather than in the prompt. This is the principle from §3.3 made operational at scale.

> **LOOM-5**: Folding MUST NOT destroy history. The full turns MUST remain accessible. Folding produces a view, not a mutation.

> **LOOM-6**: Folding MUST NOT compress the call. The system prompt and gate definitions MUST always be present in the entity's context.

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

Both techniques preserve the loom — neither destroys history. The difference is in how the entity relates to its past. Folding gives the entity programmatic access to its history through code. Compaction gives the entity a lossy summary in the prompt. Folding is a design choice. Compaction is a pressure valve.

The call is exempt from both. The system prompt, the hyperparameters, the gate definitions — these survive intact regardless of how aggressively the context is managed. The entity may lose detailed memory of what it did on turn three, but it never loses its sense of who it is and what it can do.

### 6.9 The loom as entity-readable state

The loom can also face inward. A circle MAY expose the loom — or part of it — as a readable object in the entity's sandbox. When it does, the entity can access its own history through code.

This is a circle design choice, not a mandate. Some circles expose the full loom as a queryable variable. Others expose just the current thread. Others expose nothing — the entity only sees what the circle puts in its context window. All three are valid. The spec does not require the loom to be entity-readable, but it does not prohibit it either, and the most capable systems will make use of it.

When the loom is exposed, the entity's relationship to its own history changes. Instead of passively receiving whatever the circle puts in its prompt, the entity actively explores its past through code — summarizing old turns, expanding folded sections, comparing its current approach to earlier attempts, inspecting the results of sibling threads. These are not special introspection channels built into the harness. They are ordinary code execution, using ordinary gates and sandbox primitives, operating on the loom as data. The decisions the entity makes about how to use its history show up in the trace, flow into the loom, and feed back into training. This is why thin harnesses beat smart harnesses: when the entity manages its own context through code, that intelligence compounds through training. When the harness manages context through built-in logic, that intelligence helps now but does not train into the next generation.

> **LOOM-11**: The loom MAY be exposed as a readable object within the circle's sandbox. When exposed, the entity accesses its own history through code execution, not through special observation channels.

---

## Chapter 7: Production

An entity that works in a demo and an entity that works in production are separated by a set of problems that are boring to describe and fatal to ignore. Context windows fill up. API calls fail. Tokens cost money. Protocols must be spoken. None of this changes the vocabulary — every concept from the previous six chapters applies unchanged. What changes is the operational discipline required to keep the loop running reliably, at scale, over time.

This chapter states the rules for that discipline. The conceptual ideas — ephemeral gates, dependency injection — are brief because they follow directly from the circle model. The infrastructure rules — protocols, retries, token tracking — are stated minimally because their implementations vary. What matters is the contract, not the mechanism.

### 7.1 Context management in production

For context management strategies including folding and compaction, see §6.8. The rules below govern production behavior.

> **PROD-4**: Folding MUST be triggered automatically when context approaches the crystal's limit. The trigger threshold is implementation-defined.

### 7.2 Ephemeral gates

Some gate results are large and useful for exactly one turn. A full webpage. A large file. A database dump. The entity reads the content, extracts what it needs, and moves on. Keeping the full observation in the working context wastes the crystal's window on content that has already been consumed.

An ephemeral gate's observation is replaced with a compact reference after the entity's next turn. The full content is stored in the loom — the observation is never lost — but it is removed from the entity's working context. If the entity needs the content again, it calls the gate again.

> **PROD-5**: If ephemeral gates are supported, the full observation MUST still be stored in the loom. Only the working context is trimmed.

This is an optimization, not a requirement. Implementations MAY support ephemeral gates.

### 7.3 Dependency injection

Gates close over environment state. A `read` gate knows its filesystem root. A `call_agent` gate holds a reference to the crystal it will use for child entities. A `fetch` gate may carry timeout configuration or authentication headers. These dependencies are injected when the circle is constructed, not when the entity invokes the gate.

```
// Pseudocode: configuring gate dependencies
circle = Circle({
  gates: [
    read.with({ root: "/data" }),
    fetch.with({ timeout: 5000 }),
    call_agent.with({ crystal: child_crystal, max_depth: 2 })
  ],
  wards: [max_turns(100)]
})
```

The entity calls `read("data.json")` without knowing or caring where the filesystem root is. The gate knows. The circle was prepared before the entity appeared. This is dependency injection applied to the boundary between the entity and the world — the entity describes what it wants, the gate resolves how to get it, and the configuration was fixed at construction time.

Implementations SHOULD provide a dependency injection mechanism for gates. CIRCLE-10 already requires that gate dependencies be configured at circle construction time. In practice, this means gates are partially applied functions: the host binds the dependencies, and the entity supplies the arguments.

### 7.4 Infrastructure rules

The remaining production concerns — protocols, retries, token tracking, streaming — are stated as rules with minimal commentary. Their implementations vary; the contracts do not.

> **PROD-1**: Protocol adapters MUST NOT alter the entity's behavior. The same cantrip MUST produce the same behavior regardless of whether it is accessed via CLI, HTTP, or ACP.

> **PROD-2**: Retry logic MUST be transparent to the entity. A retried crystal invocation MUST appear as a single turn, not multiple turns. Implementations SHOULD retry rate limits (429) and server errors (5xx) with exponential backoff. Client errors (4xx except 429) MUST NOT be retried.

> **PROD-3**: Token usage MUST be tracked per-turn and cumulatively per-entity.

Token counts are stored per-turn in the loom (LOOM-9) and accumulated across the entity's lifetime. They are how you track cost, detect context growth, and trigger folding.

Implementations SHOULD emit streaming events as they occur — reasoning traces, text content, gate invocations, results, token usage. Streaming is an observation channel, not a control channel. Events report what the loop is doing but do not affect its execution.

---

## Glossary

Quick reference. Terms are defined in context throughout the spec; this table is for lookup.

| # | Term | Definition |
|---|------|-----------|
| 1 | **Crystal** | The model. Stateless: messages in, response out. |
| 2 | **Call** | Immutable conditioning: system prompt + hyperparameters + gate definitions as text. |
| 3 | **Gate** | Host function that crosses the circle's boundary. |
| 4 | **Ward** | Subtractive restriction on the action space. |
| 5 | **Circle** | The environment: sandbox + gates + wards. |
| 6 | **Intent** | The goal. What the entity is trying to achieve. |
| 7 | **Cantrip** | The recipe: crystal + call + circle. A value, not a process. |
| 8 | **Entity** | What emerges when you cast a cantrip on an intent. The living instance. |
| 9 | **Turn** | One cycle: entity acts, circle responds, state accumulates. |
| 10 | **Thread** | One root-to-leaf path through the loom. A trajectory. |
| 11 | **Loom** | The tree of all turns across all runs. Append-only. |

The eleven terms have an internal structure: three primaries (crystal, call, circle), one emergent (entity — what appears when the three primaries are in relationship), and derived concepts that pair naturally (gate/ward, intent/thread, turn/loom). The cantrip is the manifest whole that contains all of them. This structure is not accidental. It reflects which concepts are fundamental, which are derived, and how they relate.

## Conformance

An implementation is conformant if:

1. It implements all eleven terms as described
2. It passes the test suite (`tests.yaml`)
3. Every behavioral rule (LOOP-*, CANTRIP-*, INTENT-*, ENTITY-*, CRYSTAL-*, CALL-*, CIRCLE-*, COMP-*, LOOM-*, PROD-*) is satisfied

Implementations MAY extend the spec with additional features as long as the core behavioral rules are preserved.

The reference implementation is TypeScript/Bun. It is one valid manifestation. The spec is the source of truth.
