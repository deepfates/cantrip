# RLM Specification (Cantrip Idiomatic, JS REPL)

## Goal
Implement a Recursive Language Model (RLM) in cantrip as a **separate loop** (not an Agent)
that uses a **persistent JS REPL environment** with true nested recursion and explicit
termination semantics, while keeping the **context outside the LLM prompt**.

## Non-Goals
- Do **not** implement RLM as an `Agent` subclass.
- Do **not** use tool calls or ReAct-style loops.
- Do **not** put full context into the LLM prompt.
- Do **not** add `llm_query_batched`.

## Prior Art Alignment
Matches the original RLM loop structure:
- Model outputs **free text + code blocks**.
- Code blocks are executed in an environment.
- Execution output is appended to history (truncated).
- Termination requires `FINAL(...)` or `FINAL_VAR(...)`.
- Recursion is **nested RLMs**, not just plain LLM calls.

## Public API
```ts
const rlm = createRLM({
  llm,            // root model (BaseChatModel)
  subLlm?,        // optional cheaper model for sub-calls
  maxDepth?,      // default 2
  maxIterations?,// default 20
  persistent?,    // default true
  systemPrompt?,  // optional override
});

const answer = await rlm.query(query, context);
```

Optional streaming:
```ts
for await (const event of rlm.query_stream(query, context)) {
  // render events
}
```

## CLI / REPL UX
- Keep existing REPL semantics: one query per line / run.
- Add a `--context <path>` flag to load context out of band.
- Context is loaded once at startup and injected into the RLM environment.
- Example:
  ```
  bun run examples/rlm_repl.ts --context data/corpus.txt
  › What are the key risks?
  ```
### CLI Context Details (Recommended)
- **Precedence**: `--context` (or `--context-dir`) always wins; stdin/args are query only.
- **Types**:
  - `.txt` / `.md` → string context
  - `.json` → object or list context
- **Directories**: `--context-dir <path>` loads multiple files in lexical order.
  - Default: list of file contents (array of strings)
  - Alternative: concatenate into one string (configurable)
- **Encoding**: assume UTF-8; fail fast on decode errors.
- **Size limit**: enforce a max byte size with a clear error (configurable).
- **Metadata**: include total char count, type, and a short preview in the prompt.
- **Failure mode**: invalid path or unreadable context aborts before REPL starts.

## Core Loop (RLM, not Agent)
1. Build prompt = system + metadata + history.
2. Ask LLM for next action.
3. Parse any ` ```repl ``` ` blocks (JS code).
4. Execute each block in a persistent `JsAsyncContext`.
5. Append truncated execution output to history as a user message.
6. Check for `FINAL(...)` or `FINAL_VAR(...)` in the LLM response text (outside code).
7. If FINAL found, return. Otherwise, continue until `maxIterations`.
8. On max iterations, issue a final prompt to force completion.

## Context Isolation
- The **full context** is placed only in the JS environment as `context`.
- The LLM prompt contains **only metadata**:
  - total character length
  - type (string | list | object)
  - optional short preview
- The LLM also sees prior **(code, truncated output)** history only.

## JS Environment Contract
Globals injected into the `JsAsyncContext`:
- `context`: the input context
- `history`: prior conversation history summaries (for persistent mode)
- `FINAL_VAR(name)`: helper to return a named variable
- `SHOW_VARS()`: helper to list user-defined variables (optional but recommended)
- `sub_rlm(query, context?)`: **async host function** that spawns a nested RLM

### `sub_rlm` semantics
- Spawns a **full RLM** with its own `JsAsyncContext` and depth+1.
- At `maxDepth`, `sub_rlm` falls back to a plain LLM call.
- Each nested RLM preserves the same loop semantics and termination rules.

## Code Block Parsing
- Execute only fenced blocks:
  ```
  ```repl
  // JS code
  ```
  ```
- All other model text is preserved as normal assistant content.
- `FINAL(...)` and `FINAL_VAR(...)` are only recognized in **non-code text**.

## Termination Rules
- Only terminate on explicit `FINAL(...)` or `FINAL_VAR(...)`.
- If `FINAL_VAR(x)` is used, evaluate `x` in the JS environment and return it.
- If no final answer after `maxIterations`, issue a final prompt to force completion.

## Truncation / History Formatting
For each code block, append:
```
Code executed:
```js
<code>
```

REPL output:
<truncated output>
```

- Default max output chars: 20k (configurable)
- Truncation should be stable and explicit.
### Redaction Guard (Recommended)
- If REPL output length exceeds **25% of context length**, replace output with:
  `[redacted: output too large]`
- Threshold should be configurable.
- Purpose: prevent accidental context dumps into the prompt history.

## Persistence & Multi-Turn History
- `persistent=true` keeps a JS context alive across multiple `query()` calls.
- Each new query adds a new `context` slot and appends prior histories to `history`.
- Prompt metadata should expose context count/history count to the model.

## Event Streaming (Optional)
Events for `query_stream` should mirror agent streams:
- `RlmTextEvent`: assistant free text
- `RlmCodeEvent`: raw code block
- `RlmExecEvent`: execution output (truncated)
- `RlmStepStartEvent` / `RlmStepCompleteEvent`: timing/status
- `RlmFinalEvent`: final answer

## Tests
Unit:
- `FINAL` and `FINAL_VAR` detection.
- Code block parsing (only `repl` fences).
- Execution output truncation.
- Max iteration fallback prompt.
- Depth-limited recursion (sub_rlm becomes plain LLM at max depth).
- Persistent history accumulation.

Integration (mocked LLM):
- Multi-step loop with code blocks and final answer.
- Nested sub_rlm calls produce isolated environments.

## Open Questions (Resolve Before Implementation)
- Should `FINAL_VAR` return JSON or stringified values?
- Do we want to allow ` ```js ``` ` fences in addition to ` ```repl ``` `?
- Exact metadata format and preview length.
