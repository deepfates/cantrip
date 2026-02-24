# Pattern Progression

This note translates the TypeScript examples into the spec's language-neutral concepts. Each example refines the same loop — **call + crystal + circle** — and shows how to operationalize it as production-grade behavior. Use this as the bridge between `SPEC.md` and `/examples`.

## Example Map

| Example | Pattern focus | Spec terms to anchor | Productionization hook |
|---------|---------------|----------------------|------------------------|
| 01–02 | Crystal and gate primitives | `CRYSTAL`, `GATE`, `done` | Swap-in provider, unit-test gates directly |
| 03–05 | Circle invariants and wards | `CIRCLE-1`, `CIRCLE-2`, `Ward` | Enforce `done`, compose safeguards before run |
| 06 | Provider portability | `CrystalProvider` | Treat the crystal as configuration, not code |
| 07–09 | Medium selection | `Medium`, `crystalView()` | Bind one medium per circle; advertise capabilities |
| 10 | Parallel delegation | `call_entity_batch`, `loom` | Capture tree-structured work for audit + retries |
| 11 | Folding | `Loom`, `folding_config` | Apply summaries before the context ceiling |
| 12 | Full agent | `Medium: js`, `safeFsGates` | Run code in a sandbox, cross filesystem via gates |
| 13 | ACP adapter | `serveCantripACP` | Expose cantrips as an editor/service endpoint |
| 14 | Recursive entities | `call_entity`, `max_depth` | Depth-limit recursion via wards |
| 15 | Research entity | `jsBrowserMedium`, `call_entity_batch` | Combine browser+JS mediums with ACP + memory |
| 16 | Familiar | `cantripGates`, `repoGates`, `JsonlStorage` | Long-lived coordinator that spawns child cantrips |

## Implemented In This Repo (Elixir)

These are the concrete default runs in `Cantrip.Examples.run/2`, intentionally ordered so capability grows pattern-by-pattern.

| Example | What it demonstrates concretely | Default result |
|---------|----------------------------------|----------------|
| 01 | minimal `done` loop | `pattern-01:minimal-done` |
| 02 | ordered gate execution (`echo` then `done`) | `pattern-02:gate-loop` |
| 03 | `require_done_tool` enforcement (text does not terminate) | `pattern-03:require-done` |
| 04 | truncation by `max_turns` ward | `nil` (truncated) |
| 05 | stop-at-`done` ordering in same utterance | `pattern-05:stop-at-done` |
| 06 | per-call crystal portability via `call_agent` crystal override | `pattern-06:openai/gemini` |
| 07 | conversation-medium tool turn followed by text termination | `pattern-07:conversation+tool` |
| 08 | code-medium `done.(...)` | `pattern-08:code` |
| 09 | state carried across code turns | `pattern-09:42` |
| 10 | parallel delegation via `call_agent_batch` | `pattern-10:parallel+delegation` |
| 11 | folding trigger and folded-context visibility | `pattern-11:folded` |
| 12 | full code agent: `read` + `compile_and_load` + module call | `pattern-12:compiled:agent-source` |
| 13 | ACP-style strict done contract (`tool_choice: "required"`) | `pattern-13:acp-ready` |
| 14 | recursive delegation with depth-bounded child calls | `pattern-14:mid:leaf` |
| 15 | research-style fanout: batch child readers + synthesis | `pattern-15:research+batch` |
| 16 | familiar-style coordinator state + persistent JSONL loom | `pattern-16:bootstrap|familiar-worker` |

## Progression Narrative

### 1. Primitives: crystals, gates, circles (Examples 01–05)
- *Intent*: prove that the spec's baselines (a crystal call and a gate execution) stand alone. Example 01 is the raw `crystal` contract — a message array in, a completion out. Example 02 highlights how gates are just typed functions with metadata (`name`, `params`).
- *Circle enforcement*: Example 03 maps directly to `CIRCLE-1` (must expose `done`) and `CIRCLE-2` (must have at least one ward). Example 05 shows how wards merge into a `ResolvedWard`, emphasizing that most restrictive numeric values win, while boolean controls such as `require_done_tool` OR together.
- *Productionization*: treat each gate like a regular service function — unit tests can call `gate.execute` without a crystal. Enforce circle invariants during configuration loading so a malformed circle never reaches runtime. Surface resolved wards in telemetry so operators know what limits apply per cast.

### 2. Provider-agnostic crystals (Example 06)
- *Intent*: follow the spec's language-neutrality by modeling the crystal as a pluggable provider. The recipe (`cantrip` call + circle) does not change when swapping Anthropic ↔ OpenAI ↔ Gemini.
- *Productionization*: define crystals in configuration (`crystal: "openai/gpt-5-mini"`) so deployments can swap providers at runtime. Maintain a validation step that checks API keys and limits before casting.

### 3. Medium physics (Examples 07–09)
- *Conversation default*: Example 07 shows that omitting a medium yields the conversation baseline — the entity "sees" gates as tool calls. This is the spec's default `medium: conversation`.
- *Code mediums*: Example 08 replaces conversation with the JS medium. Instead of textual tool calls, the crystal writes JavaScript inside QuickJS. Example 09 switches to the browser medium (Taiko). Both reinforce the spec rule: **exactly one medium per circle**; whichever medium you choose defines how the circle injects capability docs via the `crystalView()` pattern.
- *Productionization*: document each medium's physics (e.g., JS globals, `submit_answer`, Taiko APIs). Provide teardown hooks (`circle.dispose`) so headless browsers and runtimes close cleanly. When deploying, pin mediums to isolated sandboxes (QuickJS, containerized Chrome) and feed the resulting capability string into audit logs.

### 4. Delegation and tree memory (Examples 10 & 14)
- *Parallelism*: Example 10 introduces `call_entity_batch`, letting a parent entity spawn multiple child entities with independent contexts. The shared `Loom` captures every turn and gate call, aligning with the spec's requirement that a cast is observable end-to-end.
- *Recursion*: Example 14 narrows to single-child delegation via `call_entity`, enforcing `max_depth` through wards. The parent passes context into child circles, and the loom records the recursion tree.
- *Productionization*: instrument every delegated child with the parent `cantrip_id` and `parent_id` so auditors can replay the tree. Cap recursion using resolved wards, and surface the current `depth` in prompts so crystals know when they're near the limit. Provide replay tooling that reads the loom and replays turns for debugging.

### 5. Memory pressure management (Example 11)
- *Intent*: threads that exceed the context window must fold. Example 11 demonstrates `shouldFold` and `partitionForFolding` without calling a crystal, emphasizing that folding is an environment policy, not a model behavior.
- *Productionization*: configure folding thresholds (`DEFAULT_FOLDING_CONFIG`) per deployment, and emit a loom event when folding occurs. When folding is triggered, call back into a crystal to summarize the `toFold` segment and append the summary as a new turn with `metadata.folded_from`.

### 6. Operational loops (Examples 12–16)
- *Full agent (12)*: combine the JS medium with filesystem gates (`safeFsGates`). The entity runs code inside QuickJS and interacts with the host filesystem only via typed gates; wards (`max_turns`) protect the loop. This is the canonical code-agent deployment.
- *ACP adapter (13 & 15)*: `serveCantripACP` wraps a cantrip in the Agent Control Protocol so editors (VS Code, etc.) can attach. Example 15 extends this with browser automation (`jsBrowserMedium`), recursive delegation, and sliding-window memory, showing how to wire progress callbacks (`progressBinding`) back into ACP clients.
- *Familiar (16)*: a long-lived coordinator entity living inside a JS medium. It cannot touch bash or the browser directly; instead, it creates new cantrips using `cantripGates` and `cast`, handing each child its own medium. Repo observation gates (`repo_files`, `repo_read`, …) give it read-only situational awareness, while `JsonlStorage` keeps the loom persistent so the entity remembers past work. This is the spec's "entity that writes cantrips" pattern: recursion expressed as constructing new circles, not just calling `call_entity`.
- *Productionization*: isolate each medium in its own sandbox (`SandboxContext`, browser contexts, etc.) and use dependency overrides (`getSandboxContext`, `getBrowserContext`) to thread handles through. Persist the loom (`JsonlStorage`) when you need continuity across sessions; otherwise, `MemoryStorage` keeps casts ephemeral. Provide REPL and single-shot modes so the same deployment can run interactively (`runRepl`) or as a service.

## Operational Checklist

1. **Define primitives**: implement the crystal interface once, define gates with metadata, and enforce `done` + wards on every circle before casting.
2. **Select medium per circle**: conversation for tool-calling chat, JS for sandboxed code, browser for Taiko automation, bash for shell, etc. Remember: one circle → one medium.
3. **Bind wards + observability**: resolve wards into quantitative limits, publish them to telemetry, and stream every turn into a loom for auditing.
4. **Layer delegation**: add `call_entity`/`call_entity_batch` gates only when recursion or parallelism is required, and cap depth via wards to stay within `REC-DEPTH` constraints.
5. **Attach interfaces**: expose cantrips via ACP or in-process REPLs. Ensure teardown hooks dispose mediums and contexts so casts do not leak resources.
6. **Persist when needed**: use folding + persistent loom storage for long-lived entities (Familiar) so they can resume with bounded context windows.

Following this progression keeps the examples aligned with the spec: every deployment is just a recombination of the same eleven nouns, wired to the environment you need to operate in.
