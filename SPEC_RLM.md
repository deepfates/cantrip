# RLM Specification (Cantrip Idiomatic, JS REPL)

## Goal
Implement a Recursive Language Model (RLM) in cantrip as a **separate loop** (not an Agent)
that uses a **persistent JS REPL environment** with true nested recursion and explicit
termination semantics, while keeping the **context outside the LLM prompt**.

## Non-Goals
- Do **not** implement RLM as an `Agent` subclass.
- Do **not** use tool calls or ReAct-style loops.
- Do **not** put full context into the LLM prompt.
- Do **not** add `llm_query_batched` (keep it simple first).

## Research Alignment (Zhang et al. 2026)
Matches the RLM loop structure proven to scale to 10M+ tokens:
- **Environment Isolation**: Prompt contains only metadata; data lives in the REPL.
- **Symbolic Recursion**: LLM writes code that calls itself on programmatic snippets.
- **Iteration-0 Safeguard**: Prompting logic prevents immediate termination before exploration.
- **Answer Diffusion**: The model builds the answer in sandbox variables (`FINAL_VAR`).

## Public API

### Core RLM
```ts
const rlm = createRLM({
  llm,            // root model (BaseChatModel)
  subLlm?,        // optional cheaper model for sub-calls
  maxDepth: 2,    // recursion limit
  maxIterations: 20,
  persistent: true,
  usage: new UsageTracker(), // aggregate token counts
});

// context can be string, array, or object
const answer = await rlm.query(query, context);
```

### BaseChatModel Adapter (Phase 2)
The RLM will also be available as a `BaseChatModel` drop-in.
```ts
const model = new RlmAdapter({
  rlm,
  contextSelector: (msgs) => msgs[0].content // Logic to pick context
});
```

## Core Loop Logic
1.  **Initialize**: Create a `JsAsyncContext` with a fresh WASM module (per depth).
2.  **Inject**: Set `context` as a global variable. Register `llm_query` host function.
3.  **Iteration**:
    - Build prompt: System + Metadata (type, size, preview) + History.
    - LLM call: Extract ` ```repl ` blocks.
    - **Execute**: Run blocks sequentially. Collect `stdout`.
    - **Truncate**: If output > 25% of context or 10k chars, redact.
    - **Terminate**: Search non-code text for `FINAL()` or `FINAL_VAR()`.
4.  **Fallback**: At `maxIterations`, issue a forced completion prompt.

## JS Environment Contract (Globals)
- `context`: The large input data (String | Array | Object).
- `llm_query(query, context?)`: 
  - If `context` omitted, uses child's parent's context.
  - If `depth < maxDepth`, spawns nested RLM.
  - If `depth == maxDepth`, calls plain LLM.
- `FINAL_VAR(name)`: Helper to return a variable by name.
- `print(...)`: Maps to `console.log` for stdout history.

## Technical Implementation Details

### WASM Module Per Depth
Because `quickjs-emscripten` with `asyncify` supports only one suspension per instance, each recursion level MUST use a fresh WASM module.
- `JsAsyncContext.create({ module: createAsyncModule() })`

### Parser & Termination
- **Regex**: `FINAL\((.*?)\)` and `FINAL_VAR\((.*?)\)` (Multiline/Dotall).
- **Scope**: Only search text *outside* of code blocks to avoid false positives in comments.
- **Return Type**: `FINAL_VAR` should `JSON.stringify` non-string values.

### History Formatting
Each iteration is stored as:
```
Code executed:
```js
// model's code
```

Output:
// (truncated/redacted result)
```

## Event Streaming
RLM emits `AgentEvent`-compatible objects:
- `RlmTextEvent` (Thinking)
- `RlmCodeEvent` (ToolCall: repl)
- `RlmExecEvent` (ToolResult: stdout)
- `RlmFinalEvent` (FinalResponse)

## CLI / REPL UX
```bash
bun run examples/rlm_repl.ts --context data/huge_corpus.txt
```
- Supports `.json`, `.md`, `.txt`, and directories (lexical order).
- Enforces a 100MB safety limit (configurable).

## Testing Strategy
1. **Parser Tests**: Validate extraction and FINAL detection across complex text.
2. **Sandbox Tests**: Ensure `llm_query` correctly bridges data between isolated VM instances.
3. **Loop Tests**: Mock LLM to verify iteration-0 safeguard and max-iteration fallback.
4. **Integration Tests**: Oolong-style tasks (Needle in Haystack, counting) to verify "lift".