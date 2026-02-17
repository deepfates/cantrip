# Cantrip Specification

> A cantrip is the simplest spell that works.

**Version**: 0.1.0-draft
**Status**: Draft — behavioral rules for implementation

This document specifies the behavior of a cantrip implementation. It uses eleven terms precisely defined below. Any implementation that passes the accompanying test suite (`tests.yaml`) is a valid cantrip.

The spec describes *behavior*, not technology. It says "the circle must provide sandboxed code execution" — not "use QuickJS." It says "the crystal takes messages and returns a response" — not "use the Anthropic SDK."

---

## Chapter 1: The Loop

A cantrip puts a language model in a loop with an environment. The model acts. The environment responds. The model acts again. This continues until termination or truncation.

### 1.1 The turn cycle

Every cantrip follows the same cycle:

1. The **entity** receives the current context (all prior turns plus the call)
2. The entity produces an **utterance** — text that may contain executable code
3. The **circle** executes the code and produces an **observation** — return values, output, errors
4. The observation is appended to the context
5. Go to step 1

This is the irreducible unit. Everything else in the spec is structure around this cycle.

### 1.2 Termination and truncation

The loop ends in exactly one of two ways:

- **Terminated**: the entity calls the `done` gate, signaling it believes the task is complete. The entity chose to stop.
- **Truncated**: a ward cuts the entity off — max turns reached, timeout exceeded, resource limit hit. The environment chose to stop.

These are semantically different. A terminated thread's final state is terminal. A truncated thread's final state is not — the entity was interrupted, not finished. Implementations MUST record which occurred.

If the entity produces a text-only response (no code, no gate calls) and `done` is not required, the loop MAY treat that as implicit termination. If `done` IS required (the cantrip was configured with `require_done_tool: true`), the loop MUST continue until `done` is called or a ward triggers.

### 1.3 Behavioral rules

- **LOOP-1**: The loop MUST alternate between entity utterances and circle observations. Two consecutive entity utterances without an intervening observation MUST NOT occur.
- **LOOP-2**: The loop MUST terminate. Every cantrip MUST have at least one termination condition (a `done` gate, or text-only response when `done` is not required) AND at least one truncation condition (max turns ward).
- **LOOP-3**: When the `done` gate is called, the loop MUST stop after processing that gate. Any remaining gate calls in the same utterance MAY be skipped.
- **LOOP-4**: When a ward triggers truncation, the loop MUST stop. The implementation SHOULD generate a summary of what was accomplished before the entity was cut off.
- **LOOP-5**: The entity MUST receive the full context (call + all prior turns) on every iteration. The context grows monotonically within a thread (but see Chapter 6 on folding).

### 1.4 The cantrip (the recipe)

A cantrip is the recipe that binds a crystal to a circle through a call. It is a value, not a running process. You cast a cantrip on an intent to produce an entity.

```
cantrip = crystal + call + circle
entity = cast(cantrip, intent)
```

A cantrip can be cast multiple times on different intents, producing different entities with different episodes. The cantrip itself doesn't change.

**Behavioral rules:**

- **CANTRIP-1**: A cantrip MUST contain a crystal, a call, and a circle. Missing any of these is invalid.
- **CANTRIP-2**: A cantrip is a value. It MUST be reusable — casting it multiple times on different intents MUST produce independent entities.
- **CANTRIP-3**: Constructing a cantrip MUST validate that the circle has a `done` gate (CIRCLE-1) and at least one truncation ward (CIRCLE-2).

### 1.5 The intent

The intent is what the entity is trying to achieve — the reason the cantrip was cast. It is the `q` in `RLM_M(q, C)`.

Same cantrip + different intent = different episode with different success criteria.

**Behavioral rules:**

- **INTENT-1**: The intent MUST be provided when casting a cantrip. A cantrip cannot be cast without an intent.
- **INTENT-2**: The intent MUST appear as the first user message in the entity's context, after the system prompt (if any).
- **INTENT-3**: The intent is immutable for the lifetime of the entity. The entity cannot change its own intent.

### 1.6 The entity

The entity is the living instance — the crystal shaped by its call, placed inside the circle, pursuing an intent, accumulating experience turn by turn. It is what emerges when crystal meets circle meets intent.

The entity exists from cast to termination/truncation. It has a growing context (the thread-in-progress) and sandbox state.

**Behavioral rules:**

- **ENTITY-1**: An entity MUST be produced by casting a cantrip on an intent. There is no other way to create an entity.
- **ENTITY-2**: Each entity MUST have a unique ID.
- **ENTITY-3**: An entity's context MUST grow monotonically within a thread (modulo folding, which is a view transformation, not context deletion).
- **ENTITY-4**: When an entity terminates or is truncated, its thread persists in the loom. The entity ceases but its record endures.

### 1.7 Minimal cantrip

The smallest valid cantrip requires:
- A crystal (even a fake one that returns hardcoded text)
- A circle with at least one gate (`done`)
- A max turns ward (to guarantee truncation as a safety net)
- An intent (the query string)

```
cantrip = {
  crystal: any_crystal,
  circle: { gates: [done], wards: [max_turns(200)] },
  call: { system_prompt: null }
}
entity = cast(cantrip, intent="say hello")
// The loop runs until done is called or 200 turns elapse
```

---

## Chapter 2: The Crystal

The crystal is the model — frozen weights, latent intelligence, compressed from the corpus of human expression. It can't act on its own. It can only respond to context.

### 2.1 The crystal contract

A crystal is anything that satisfies this interface:

```
crystal.invoke(messages: Message[], tools?: ToolDefinition[], tool_choice?: ToolChoice) -> Response
```

Where:
- `messages` is an ordered list of messages (system, user, assistant, tool)
- `tools` is an optional list of gate definitions (JSON Schema)
- `tool_choice` controls whether the crystal must use gates ("required"), may use them ("auto"), or must not ("none")

The response contains:
- `content`: text output (may be null if the crystal only made gate calls)
- `tool_calls`: an optional list of gate invocations, each with an ID, gate name, and JSON arguments
- `usage`: token counts (prompt, completion, cached)
- `thinking`: optional reasoning trace (for models that support extended thinking)

### 2.2 Swappability

Same circle, same call, different crystal = different behavior, same loop. The crystal is the one thing you swap to change *how* the entity thinks without changing *what* it can do.

### 2.3 Provider implementations

The spec requires support for at least these provider families:
- **Anthropic** (Claude models)
- **OpenAI** (GPT models)
- **Google** (Gemini models)
- **OpenRouter** (proxy to many providers)
- **Local** (Ollama, vLLM, any OpenAI-compatible endpoint)

Each provider implementation translates the crystal contract into the provider's native API. The implementation details (authentication, streaming, rate limiting) are provider-specific and not part of the spec.

### 2.4 Behavioral rules

- **CRYSTAL-1**: A crystal MUST be stateless. Given the same messages and tool definitions, it SHOULD produce similar output (modulo sampling). It MUST NOT maintain internal state between invocations.
- **CRYSTAL-2**: A crystal MUST accept an arbitrary number of messages. Context window limits are the crystal's problem, not the caller's (but see folding in Chapter 6).
- **CRYSTAL-3**: A crystal MUST return at least one of `content` or `tool_calls`. A response with neither is invalid.
- **CRYSTAL-4**: Each `tool_call` MUST include a unique ID, the gate name, and arguments as a JSON string.
- **CRYSTAL-5**: If `tool_choice` is "required", the crystal MUST return at least one tool call. If the provider doesn't support forcing tool use, the implementation MUST simulate it (e.g., by re-prompting).
- **CRYSTAL-6**: Provider implementations MUST normalize responses to the common crystal contract. Provider-specific fields (stop_reason, model ID, etc.) MAY be preserved as metadata but MUST NOT be required by consumers.

---

## Chapter 3: The Call

The call is the immutable conditioning — everything that shapes how the crystal behaves before any intent arrives.

### 3.1 What the call contains

The call is the union of:
1. **System prompt** — persona, behavioral directives, domain knowledge
2. **Hyperparameters** — temperature, top_p, max_tokens, stop sequences, sampling config
3. **Gate definitions as text** — the circle's interface rendered for the crystal to perceive

The third element is crucial. The crystal doesn't see "tools" as a separate mechanism. It sees text that describes what it can do. OpenAI's Harmony renderer proves this concretely: JSON Schema gate definitions are transpiled to TypeScript and injected as text in the prompt. The call is how the circle presents itself to the crystal.

### 3.2 Immutability

The call is fixed for the lifetime of a cantrip instance. You can create a new cantrip with a different call, but you cannot mutate the call of an existing one.

Same crystal + different call = different entity behavior.
Same crystal + same call + different intent = different episode.

### 3.3 What the call is NOT

Dynamic context — retrieved documents, injected state, programmatic insertions that change per turn — is NOT part of the call. It is circle state, accessed through gates. The call is small and fixed. The circle holds the data. The entity explores it through code.

This follows from the RLM insight: context belongs in the environment as a variable (`C`), not crammed into the prompt.

### 3.4 Behavioral rules

- **CALL-1**: The call MUST be set at cantrip construction time and MUST NOT change afterward.
- **CALL-2**: If a system prompt is provided, it MUST be the first message in every context sent to the crystal. It MUST be present in every invocation, unchanged.
- **CALL-3**: Gate definitions MUST be derived from the circle's registered gates. Adding or removing a gate changes the call (which means creating a new cantrip, not mutating this one).
- **CALL-4**: The call MUST be stored in the loom as the root context. Every thread starts from the same call.
- **CALL-5**: Folding (context compression) MUST NOT alter the call. The entity always retains its full conditioning. Only the trajectory (turns) may be folded.

---

## Chapter 4: The Circle

The circle is the environment where the entity acts. It is a sandbox with gates to the outside world and wards that constrain what's allowed.

### 4.1 Circle types

A circle can be anything that receives the entity's output and returns observations:
- A **human** in a chat — the human's brain is the sandbox, their reply is the observation
- A **REPL** — the entity writes code, the sandbox executes it, the result comes back
- A **shell** — command execution and output
- A **browser** — page interaction and DOM observations

The difference is *verifiability*: a human's response is rich but unreproducible; a REPL's output is exact, replayable, and trainable. Cantrip builds for code circles — environments where the ground pushes back with verifiable truth.

### 4.2 Code circles

In a code circle, the entity gets a full execution context — a sandbox where it can write and run arbitrary code. The action space is:

```
A = (L + G) − W
```

Where:
- **L** = language primitives (builtins, math, strings, control flow, data structures — whatever the sandbox provides)
- **G** = registered gates (host functions that cross the boundary)
- **W** = wards (restrictions that remove or constrain elements of L + G)

This is compositional. The entity can combine primitives and gates in ways you didn't enumerate. That's the difference between code-as-action-space and tool-calling: in tool-calling, the action space is a finite list of JSON schemas. In a code circle, it's a programming language.

### 4.3 Tool-calling circles

When the crystal uses structured tool calls (JSON function invocations) rather than writing code in a sandbox, this is a constrained case of the circle model. The action space collapses to just G — the entity can only invoke gates by name with JSON arguments, not compose them with language primitives.

Tool-calling circles are valid. They're how most agents work today. But they sacrifice compositionality. A code circle lets the entity write `for (const doc of context.documents) { if (doc.relevant) call_agent(doc) }`. A tool-calling circle requires the entity to make one tool call at a time.

Implementations MUST support tool-calling circles. Implementations SHOULD support code circles.

### 4.4 Gates

Gates are host functions — crossing points through the circle's boundary. Inside the circle, the entity can do anything the language allows. Gates are how effects cross the boundary.

Every circle MUST have at least one gate: `done`.

Common gates:
- `done(answer)` — signal task completion, return the answer
- `call_agent(intent, config?)` — cast a child cantrip on a derived intent
- `call_agent_batch(intents)` — cast multiple child cantrips in parallel
- `read(path)` — read from the filesystem
- `write(path, content)` — write to the filesystem
- `fetch(url)` — HTTP request
- `goto(url)` / `click(selector)` — browser interaction

Gates close over environment state — a filesystem root, a browser instance, a crystal for sub-cantrips. You configure what each gate has access to when you prepare the circle. This is dependency injection for gates.

### 4.5 Wards

Wards are subtractive. They reduce the action space. The entity starts with the full surface (L + G); wards carve it down to A.

- A ward removes a gate (shrinks G) — "no network access"
- A ward restricts a gate's reach (narrows what a gate can do) — "read only from /data"
- A ward caps turns (bounds the episode) — "max 200 turns"
- A ward limits resources — "max 1M tokens", "timeout after 5 minutes"

Wards are not permissions granted from nothing. They are restrictions applied to the full surface. This follows the Bitter Lesson: abstractions that constrain the action space fight against model capability. Give the entity the fullest possible action space, then ward off what's dangerous.

### 4.6 Security

The lethal trifecta — private data access + untrusted content exposure + external communication — is about which gates exist in the same circle. Security means warding: removing one of those gates, or isolating capabilities across separate circles.

### 4.7 Circle state

The circle maintains state between turns:
- **Sandbox state** — variables, data structures, intermediate results that persist across turns within the same entity
- **External state** — filesystem, database, browser DOM — whatever the gates have access to

Circle state is distinct from the message history. The message history is what the crystal sees. Circle state is what the sandbox knows. Both grow across turns.

### 4.8 Behavioral rules

- **CIRCLE-1**: A circle MUST provide at least the `done` gate.
- **CIRCLE-2**: A circle MUST have at least one ward that guarantees termination (max turns, timeout, or similar). A cantrip that can run forever is invalid.
- **CIRCLE-3**: Gate execution MUST be synchronous from the entity's perspective — the entity sends a gate call, the circle executes it, the observation returns before the next turn begins.
- **CIRCLE-4**: Gate results MUST be returned as observations in the context. The entity MUST be able to see what its gate calls returned.
- **CIRCLE-5**: If a gate call fails (throws an error), the error MUST be returned as an observation, not swallowed. The entity MUST see its failures.
- **CIRCLE-6**: Wards MUST be enforced by the circle, not by the entity. The entity cannot bypass a ward. Wards are environmental constraints.
- **CIRCLE-7**: If multiple gate calls appear in a single utterance, the circle MUST execute them in order and return each result as a separate observation. Implementations MAY execute independent gate calls in parallel.
- **CIRCLE-8**: The `done` gate MUST accept at least one argument: the answer/result. When `done` is called, the loop terminates with that result.
- **CIRCLE-9**: In a code circle, sandbox state MUST persist across turns within the same entity. A variable set in turn 3 MUST be readable in turn 4.
- **CIRCLE-10**: Gate dependencies (injected resources) MUST be configured at circle construction time, not at gate invocation time.

---

## Chapter 5: Composition

An entity can summon other entities. This is how complex tasks decompose into manageable sub-tasks.

### 5.1 The `call_agent` gate

`call_agent` casts a child cantrip on a derived intent:

```
result = call_agent({
  intent: "Summarize this document",
  context?: any,        // data injected into child's circle
  system_prompt?: string, // child's call (defaults to parent's)
  max_depth?: number     // recursion limit ward
})
```

A new entity appears in its own circle, does work, and returns a result. The child's circle is carved from the parent's — you can't grant gates you don't have.

### 5.2 Batch composition

`call_agent_batch` spawns multiple children in parallel:

```
results = call_agent_batch([
  { intent: "Summarize chunk 1", context: chunk1 },
  { intent: "Summarize chunk 2", context: chunk2 },
  // ...
])
```

The children execute concurrently. All results are returned as an array in the order they were requested.

### 5.3 The RLM pattern

The canonical composition pattern: data lives in the circle as a variable, not crammed into the prompt. The entity writes code to explore it, recursively delegating to sub-entities for chunks too large to process at once.

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

The data never enters the prompt. The entity navigates it through code. Sub-entities handle pieces. This is how you process data that exceeds any single context window.

### 5.4 Depth limits

Composition is recursive — a child can call `call_agent` too. To prevent infinite recursion:

- Every cantrip has a `max_depth` ward (default: 1)
- Depth 0 means no `call_agent` allowed
- Each child's depth limit is parent's depth minus 1
- When depth reaches 0, the `call_agent` gate is warded off

### 5.5 Behavioral rules

- **COMP-1**: A child entity's circle MUST be a subset of the parent's circle. You cannot grant gates the parent doesn't have.
- **COMP-2**: `call_agent` MUST block the parent entity until the child completes. The parent receives the child's result as a return value.
- **COMP-3**: `call_agent_batch` MUST execute children concurrently. Results MUST be returned in request order, not completion order.
- **COMP-4**: A child entity MUST have its own independent context (message history). The child does not inherit the parent's conversation history.
- **COMP-5**: A child entity's turns MUST be recorded in the loom as a subtree. The child's root turn references the parent turn that spawned it.
- **COMP-6**: When `max_depth` reaches 0, the `call_agent` and `call_agent_batch` gates MUST be removed from the circle (warded off). Attempts to call them MUST fail with a clear error.
- **COMP-7**: The child's crystal MAY differ from the parent's crystal (if the `call_agent` config specifies a different one). The child's call MAY differ. Only the circle is inherited (subtractive).
- **COMP-8**: If a child entity fails (throws an error, not `done`), the error MUST be returned to the parent as the gate result. The parent MUST NOT be terminated by a child's failure.

---

## Chapter 6: The Loom

Everything is recorded. Every turn — every utterance, every observation — is a node in a tree. One path through the tree is a thread. All threads form the loom.

### 6.1 Turns as nodes

Each turn is stored as a record with:

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

### 6.2 Threads

A thread is a path through the turn tree from root to leaf. Threads are implicit — they emerge from the parent references on turns. You don't store threads separately.

A thread has exactly one of these terminal states:
- **Terminated**: the final turn called `done`
- **Truncated**: a ward stopped the entity
- **Active**: the entity is still running (only during execution)

### 6.3 The loom

The loom is the tree of all turns produced by a cantrip across all its runs. It is:
- **The debugging trace** — walk any thread to see every decision
- **The entity's memory** — context for forking, folding, and replaying
- **The training data** — each turn is a (context, action, observation) triple, each thread is a trajectory, reward slots are already there
- **The proof of work** — evidence of what the entity did and why

### 6.4 Storage

Turns are appended as they happen. The loom is append-only — turns are never deleted or modified after creation (but reward may be assigned later).

The reference storage format is JSONL — one JSON object per line, one turn per line, appended in chronological order. Implementations MAY use other storage backends as long as the append-only semantic is preserved.

### 6.5 Forking

Forking creates a new turn whose parent is an earlier turn in the tree, diverging from the original continuation.

```
// Original thread: turns 1 → 2 → 3 → 4 → 5
// Fork from turn 3:
// turns 1 → 2 → 3 → 4 → 5   (original thread)
//                  ↘ 6 → 7   (forked thread)
```

A forked entity starts with the context from the fork point — all turns from root to the fork turn. The original thread is untouched. The new thread grows independently.

Forking is NOT an environment reset. The forked entity continues from prior state, not from scratch.

### 6.6 Folding

When the accumulated context exceeds the crystal's capacity, turns can be folded — compressed into a summary node.

Folding is a view, not a mutation. The full turns remain in the loom. A folded view replaces a range of turns with a summary for the entity's working context while preserving the complete history underneath.

```
// Full loom: turns 1, 2, 3, 4, 5, 6, 7, 8
// Folded view for entity: [summary of 1-5], 6, 7, 8
// Full loom unchanged: turns 1, 2, 3, 4, 5, 6, 7, 8
```

The call is NEVER folded. Only trajectory turns may be compressed. The entity always retains its full conditioning.

### 6.7 Reward

The loom stores a reward slot on every turn. What fills it is up to the implementation:

- **Implicit reward** — did the gate succeed? Did the code throw? Gate-level success/failure is a natural per-turn signal.
- **Explicit reward** — a score attached after the fact (human rating, automated verifier, a verifier entity)
- **Shaped reward** — intermediate rewards computed by a scoring function that's part of the circle definition

For in-context learning (within a session), implicit reward is enough — the entity sees what worked in its context window. For training across sessions (RL on the loom), you need explicit reward annotation.

### 6.8 Composition in the loom

When `call_agent` spawns a child entity, the child's turns form a subtree in the parent's loom:

```
Parent turn 1
Parent turn 2 (calls call_agent)
├── Child turn 1
├── Child turn 2
└── Child turn 3 (done)
Parent turn 3 (receives child result)
```

The child's root turn has `parent_id` pointing to the parent turn that spawned it. The parent's next turn (after the child completes) has `parent_id` pointing to the parent's previous turn, not to the child.

### 6.9 Behavioral rules

- **LOOM-1**: Every turn MUST be recorded in the loom before the next turn begins. Turns are never lost.
- **LOOM-2**: Each turn MUST have a unique ID and a reference to its parent (null for root turns).
- **LOOM-3**: The loom MUST be append-only. Turns MUST NOT be deleted or modified after creation. Reward annotation is the exception — reward MAY be assigned or updated after creation.
- **LOOM-4**: Forking from turn N MUST produce a new entity whose initial context is the path from root to turn N. The original thread MUST be unaffected.
- **LOOM-5**: Folding MUST NOT destroy history. The full turns MUST remain accessible. Folding produces a view, not a mutation.
- **LOOM-6**: Folding MUST NOT compress the call. The system prompt and gate definitions MUST always be present in the entity's context.
- **LOOM-7**: The loom MUST record whether each terminal turn was terminated (entity called `done`) or truncated (ward stopped the entity).
- **LOOM-8**: Child entity turns from `call_agent` MUST be stored in the same loom as the parent, with parent references linking them to the spawning turn.
- **LOOM-9**: Each turn MUST record token usage (prompt, completion, cached) and wall-clock duration.
- **LOOM-10**: The loom MUST support extracting any root-to-leaf path as a thread (trajectory) for export, replay, or training.

---

## Chapter 7: Production

Running a cantrip in the real world. No new vocabulary — this chapter is about operating what you've built.

### 7.1 Protocols

An entity can be exposed through multiple protocols:

- **CLI** — stdin/stdout, the simplest interface
- **HTTP** — request/response or streaming
- **ACP** (Agent Communication Protocol) — for integration with editors and other agents

The protocol layer translates external requests into intents and entity responses into protocol-appropriate output. The entity doesn't know or care which protocol is being used.

### 7.2 Streaming

During execution, implementations SHOULD emit events as they occur:

- **ThinkingEvent** — reasoning trace from the crystal
- **TextEvent** — text content from the entity's utterance
- **ToolCallEvent** — gate invocation (name, arguments, ID)
- **ToolResultEvent** — gate result (output, error status)
- **StepStartEvent** / **StepCompleteEvent** — turn lifecycle
- **UsageEvent** — token counts after each crystal invocation
- **FinalResponseEvent** — the entity's final answer

Streaming is an observation channel, not a control channel. Events are informational — they don't affect the loop's execution.

### 7.3 Retries

Crystal invocations may fail due to rate limits, server errors, or transient issues. Implementations SHOULD support automatic retries with exponential backoff.

Default retry configuration:
- Max retries: 5
- Retryable status codes: 429, 500, 502, 503, 504
- Base delay: 1 second
- Max delay: 60 seconds
- Backoff: exponential with jitter

Non-retryable errors (400, 401, 403, 404) MUST NOT be retried.

### 7.4 Token management

Implementations MUST track cumulative token usage across all crystal invocations within an entity's lifetime. This includes:
- Prompt tokens (input)
- Completion tokens (output)
- Cached tokens (prompt tokens served from cache)

Usage SHOULD be stored per-turn in the loom.

### 7.5 Folding strategies

When the entity's context approaches the crystal's limit, folding kicks in. Strategies include:

- **Sliding window** — keep the last N turns, fold everything before them
- **Summary** — use the crystal to generate a summary of folded turns
- **Selective** — fold tool results but keep entity reasoning

The spec doesn't mandate a strategy. The spec mandates that folding is non-destructive (LOOM-5, LOOM-6).

### 7.6 Ephemeral gates

Some gate results are large and only useful for one turn (e.g., a full webpage, a large file). An ephemeral gate's observation is replaced with a reference after the next turn — the full content is stored in the loom but removed from the entity's working context.

This is an optimization, not a requirement. Implementations MAY support ephemeral gates.

### 7.7 Dependency injection

Gates often need access to shared resources — a filesystem root, a browser instance, a crystal for sub-cantrips. These dependencies are injected when the circle is constructed, not when gates are invoked.

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

Implementations SHOULD provide a dependency injection mechanism for gates.

### 7.8 Behavioral rules

- **PROD-1**: Protocol adapters MUST NOT alter the entity's behavior. The same cantrip MUST produce the same behavior regardless of whether it's accessed via CLI, HTTP, or ACP.
- **PROD-2**: Retry logic MUST be transparent to the entity. A retried crystal invocation MUST appear as a single turn, not multiple turns.
- **PROD-3**: Token usage MUST be tracked per-turn and cumulatively per-entity.
- **PROD-4**: Folding MUST be triggered automatically when context approaches the crystal's limit. The trigger threshold is implementation-defined.
- **PROD-5**: If ephemeral gates are supported, the full observation MUST still be stored in the loom. Only the working context is trimmed.

---

## Glossary

The eleven terms, in dependency order:

| # | Term | Definition |
|---|------|-----------|
| 1 | **Crystal** | The model — frozen weights, latent intelligence. Takes messages, returns text. Stateless. |
| 2 | **Call** | Immutable conditioning — system prompt, hyperparameters, gate definitions as text. Fixed per cantrip. |
| 3 | **Gate** | Host function — crossing point through the circle's boundary. How effects reach the outside world. |
| 4 | **Ward** | Restriction on the action space. Subtractive — removes or constrains elements of L + G. |
| 5 | **Circle** | The environment — sandbox + gates + wards. Where the entity acts. |
| 6 | **Intent** | What the entity is trying to achieve. The reason the cantrip was cast. |
| 7 | **Cantrip** | The spell — crystal + call + circle. The recipe for summoning an entity. |
| 8 | **Entity** | The living instance — crystal-in-context, pursuing an intent, accumulating experience turn by turn. |
| 9 | **Turn** | One cycle: the entity acts, the circle responds, state accumulates. The irreducible unit. |
| 10 | **Thread** | One complete run — a root-to-leaf path through the loom. A trajectory. |
| 11 | **Loom** | The tree of all turns. Every path explored, every fork taken. Append-only. The most valuable artifact. |

## The RL correspondence

The mapping is precise, not metaphorical:

| RL concept | Cantrip equivalent | Notes |
|-----------|-------------------|-------|
| Policy π | Crystal + Call | Frozen weights conditioned by immutable prompt and gate definitions |
| Task specification | Intent | What shapes which actions are good |
| State s | Circle state + context at turn t | Grows every turn (unusual in RL) |
| Action a | Code the entity writes | A = (L + G) − W |
| Observation o | Gate return values + sandbox output | Rich, unstructured |
| Reward r | Per-turn or per-thread signal | Implicit (gate success/failure) or explicit (verifier score) |
| Terminated | `done` gate called | Entity chose to stop |
| Truncated | Ward triggered | Environment chose to stop |
| Trajectory τ | Thread | One root-to-leaf path |
| Episode | Entity lifetime | First turn to termination/truncation |
| Replay buffer | Loom | All threads, all runs |
| Environment reset | New entity, clean circle | Forking is NOT a reset |

---

## Conformance

An implementation is conformant if:

1. It implements all eleven terms as described
2. It passes the test suite (`tests.yaml`)
3. Every behavioral rule (LOOP-*, CANTRIP-*, INTENT-*, ENTITY-*, CRYSTAL-*, CALL-*, CIRCLE-*, COMP-*, LOOM-*, PROD-*) is satisfied

Implementations MAY extend the spec with additional features as long as the core behavioral rules are preserved.

The reference implementation is TypeScript/Bun. It is one valid manifestation. The spec is the source of truth.
