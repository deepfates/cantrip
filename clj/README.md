# cantrip — Clojure

> Clojure realization. SCI sandbox, multimethod dispatch, and the only conformance runner that executes tests.yaml directly.

This is the Clojure realization of the cantrip spec. It was generated from SPEC.md, then refined through interactive debugging with real LLMs (primarily gpt-5-mini via OpenAI-compatible endpoints). It implements the full domain model in idiomatic Clojure: immutable cantrip values, atom-based entity state, multimethod dispatch for mediums, and a SCI (Small Clojure Interpreter) sandbox for the code medium.

For the full vocabulary and behavioral rules, see [SPEC.md](../SPEC.md) at the repo root.

---

## Quick Start

```bash
cd clj
cp .env.example .env   # add your API key
```

Run the unit tests:

```bash
clojure -M:test
```

Run the YAML conformance suite (executes tests.yaml against this implementation):

```bash
make conformance
```

Run an example in scripted mode (no API key needed):

```clojure
;; In a REPL:
(require '[cantrip.examples :as ex])
(ex/example-04-cantrip {:mode :scripted})
```

---

## Minimal Example

```clojure
(require '[cantrip.runtime :as runtime]
         '[cantrip.llm :as llm])

;; LLM — any OpenAI-compatible endpoint
(def llm-config {:provider :openai
                 :model "gpt-4.1-mini"
                 :api-key "sk-..."})

;; Cantrip — llm + identity + circle
(def spell
  (runtime/new-cantrip
   {:llm llm-config
    :identity {:system-prompt "You are a financial analyst. Call done(answer) with your summary."
               :require-done-tool false}
    :circle {:medium :conversation
             :gates [:done]
             :wards [{:max-turns 10}]}}))

;; Cast it on an intent
(def result (runtime/cast spell "Revenue up 14% QoQ, churn down 2 points. Summarize."))
(:result result)
```

No medium specified or `:conversation` — gates appear as tool definitions in the LLM's tool list. Set `:medium :code` to upgrade the action space to a SCI sandbox.

---

## Core API

### `runtime/new-cantrip`

Validates and returns a cantrip value. Enforces CANTRIP-1 (requires `:llm`, `:identity`, `:circle`), CIRCLE-1 (requires `:done` gate), and CIRCLE-2 (requires at least one truncation ward).

### `runtime/cast`

One-shot: validates, creates a fresh entity, runs the loop, returns a result map.

```clojure
(def result (runtime/cast spell "Analyze this data"))
;; => {:status :terminated, :result "...", :turns [...], :loom {...}, :cumulative-usage {...}}
```

### `runtime/summon` / `runtime/send`

Persistent entity: survives its first intent, accumulates state across sends.

```clojure
(def entity (runtime/summon spell))
(def r1 (runtime/send entity "Set up the framework"))
(def r2 (runtime/send entity "Now analyze Q3"))  ;; remembers r1
```

### `runtime/call-agent` / `runtime/call-agent-batch`

Child delegation — used internally by the code medium's `call-agent` function, but also callable directly for testing or custom composition.

---

## Mediums

### Conversation (default)

Gates appear as tool definitions in the LLM's `tools` parameter. The LLM returns structured tool calls. `tool_choice` defaults to `"auto"`.

```clojure
{:medium :conversation
 :gates [:echo :done]
 :wards [{:max-turns 5}]}
```

### Code (SCI Sandbox)

The entity writes Clojure code that executes in a [SCI](https://github.com/babashka/sci) (Small Clojure Interpreter) sandbox. The LLM sees a single `clojure` tool. Gates are projected as functions in the sandbox: `submit-answer`, `call-gate`, `call-agent`, `call-agent-batch`.

```clojure
{:medium :code
 :gates [:done :call-entity]
 :wards [{:max-turns 10}]}
```

In the sandbox, the entity writes:

```clojure
;; Turn 1
(def data (call-gate "repo_read" {"path" "metrics.txt"}))

;; Turn 2 — data persists
(submit-answer (str "Found " (count (clojure.string/split-lines data)) " lines"))
```

SCI restrictions: no Java interop (`Math/round`, `System/exit`), no `require`/`ns` (unless warded on), no `eval`, `slurp`, or other dangerous forms. The capability text documents these constraints, but gpt-5-mini consistently writes Java interop anyway — children error-steer through all turns, which is slow but functional.

**Important:** `call-agent` is **synchronous** in SCI. It blocks and returns the child's answer as a string. `submit-answer` and `call-gate` are **emit-based** — they queue actions and return nil.

### Minecraft

An experimental medium that extends code with world-facing bindings: `player-fn`, `xyz-fn`, `block-fn`, `set-block-fn`. Not used by the grimoire examples.

---

## Composition

In code medium, the entity delegates via `call-agent`:

```clojure
;; Parent writes this in the SCI sandbox:
(def trends (call-agent {"intent" "Identify top 3 trends in Q3 data..."}))
(def risks (call-agent {"intent" "What are the biggest risks..."}))
(submit-answer (str "Trends: " trends "\nRisks: " risks))
```

Children get a generic system prompt ("You are a child entity. Pursue the intent and return the result."), no delegation gates (preventing recursive delegation), and max-turns capped at 3. This was a key fix — children previously inherited the parent's coordinator prompt and tried to delegate recursively.

---

## Examples

Thirteen examples in `src/cantrip/examples.clj`, plus ACP and Minecraft-adapted variants.

| # | Pattern | What it teaches |
|---|---------|----------------|
| 01 | LLM Query | Stateless round-trip (LLM-1) |
| 02 | Gate | Observation ordering, done semantics (CIRCLE-7, LOOP-7) |
| 03 | Circle | Construction invariants (CIRCLE-1, CIRCLE-2) |
| 04 | Cantrip | Reusable value, independent casts (CANTRIP-2) |
| 05 | Wards | Subtractive composition (WARD-1) |
| 06 | Providers | Portability contract — fake vs real (LLM-1) |
| 07 | Conversation | Conversation medium baseline |
| 08 | Code | SCI sandbox + submit-answer (MEDIUM-3) |
| 09 | Capability | Capability text exposure — what the LLM sees |
| 10 | Batch | call-agent-batch with parallel children (COMP-3) |
| 11 | Folding | Message compression with max-turns-in-context |
| 12 | Code Agent | Full code-agent loop with error steering |
| 13 | ACP | Session flow (PROD-6, PROD-7) |

Run in scripted mode (no API key):
```clojure
(require '[cantrip.examples :as ex])
(ex/example-04-cantrip {:mode :scripted})
```

Run with real LLM:
```clojure
(ex/example-04-cantrip)  ;; reads from .env
```

---

## What You Can Learn Here

**Strengths:**

- **The conformance runner.** `conformance.clj` (909 lines) is a YAML test runner that loads `tests.yaml`, normalizes test specs, builds cantrips dynamically, and executes them. It's the only implementation that runs the spec's test suite directly rather than translating tests into the host language's test framework. If you want to understand how tests.yaml maps to behavior, read this.
- **Multimethod dispatch for mediums.** Medium execution is a `defmulti` dispatching on `:medium` — clean, extensible, idiomatic Clojure. Adding a new medium is one `defmethod`.
- **SCI sandbox semantics.** The SCI code medium is a real interpreter with real restrictions — you can study how capability text, forbidden symbols, and form validation interact to constrain the action space.
- **Immutable cantrip, atom-based entity.** The cast/summon/send lifecycle is the clearest expression of the spec's value-vs-process distinction. Cantrips are plain maps. Entities are maps with atoms.
- **Secret redaction.** `redaction.clj` filters API keys from loom exports and ACP output — the only implementation with this built in.

**Limitations:**

- **One LLM provider.** OpenAI-compatible only (like Python). No native Anthropic or Google adapters.
- **SCI + gpt-5-mini friction.** gpt-5-mini consistently writes Java interop (`Math/round`, `Math/exp`) despite capability text saying not to. Children error-steer through all turns. Works, but slowly (~5-10 minutes for familiar-style examples).
- **conformance.clj lives in `src/`.** A 909-line test transpiler in the source tree. It works, but it's not clear whether it should be in `src/` or `test/`.
- **Hand-rolled dotenv.** No dependency on a dotenv library — the env loader is ~30 lines of custom parsing.

---

## Architecture

```
src/cantrip/
├── runtime.clj       # Core loop: new-cantrip, cast, summon, send, call-agent
├── domain.clj        # Validation (CANTRIP-1, CIRCLE-1, CIRCLE-2, INTENT-1)
├── llm.clj           # LLM query interface (fake + OpenAI)
├── circle.clj        # Gate execution engine
├── gates.clj         # Gate metadata and tool projection
├── medium.clj        # Multimethod dispatch: conversation, code, minecraft
├── loom.clj          # Append-only turn history
├── redaction.clj     # Secret filtering for logs and exports
├── conformance.clj   # YAML test suite runner
├── examples.clj      # 13 teaching examples
└── protocol/acp.clj  # ACP session router (JSON-RPC)
```

Dependencies: Clojure 1.12, [SCI](https://github.com/babashka/sci) 0.10.48, clojure.data.json 2.5.1.

---

## Spec Conformance

Tests: **110 tests, 261 assertions** (`clojure -M:test`)

The YAML conformance runner additionally validates against `tests.yaml` directly:

```bash
make conformance
```

---

## Setup

Requires Clojure CLI (`clojure`). Ruby required for conformance preflight only.

```bash
cp .env.example .env
# Edit .env:
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-5-mini
```

Run tests:
```bash
clojure -M:test
```
