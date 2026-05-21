# Cantrip

Cantrip is an Elixir/OTP runtime for recursive language-model programs.

A cantrip binds an LLM, an identity, and a circle into a reusable
program. The circle defines the medium the entity thinks in, the gates it
can cross, and the wards that bound its action space:

```text
A = M union G - W
```

Cantrip includes supervised entities, conversation/code/bash mediums,
recursive child calls, batch fanout, streaming events, ACP integration,
Mnesia/DETS/JSONL loom storage, redaction, telemetry, diagnostics, and a
production-oriented Familiar that reasons in Elixir and delegates to
child entities.

For the vocabulary and behavioral contract, see [SPEC.md](./SPEC.md) and
[tests.yaml](./tests.yaml).

Earlier TypeScript, Python, and Clojure implementations were learning
and reference artifacts. Their useful lessons are preserved in
[docs/legacy-implementation-harvest.md](https://github.com/deepfates/grimoire/blob/main/docs/legacy-implementation-harvest.md)
and open contract gaps are tracked in
[docs/legacy-contract-backlog.md](https://github.com/deepfates/grimoire/blob/main/docs/legacy-contract-backlog.md).
The old code remains available through git history.

## Quick Start

```bash
mix deps.get
cp .env.example .env
mix verify
```

Run a deterministic example with no API key:

```bash
mix cantrip.example 04 --fake
```

Run the Familiar:

```bash
mix cantrip.familiar
```

Run the Familiar as an ACP server:

```bash
mix cantrip.familiar --acp
```

## Minimal Example

```elixir
{:ok, cantrip} =
  Cantrip.new(%{
    llm:
      {Cantrip.FakeLLM,
       %{
         responses: [
           %{tool_calls: [%{gate: "done", args: %{answer: "Revenue improved."}}]}
         ]
       }},
    identity: %{system_prompt: "You are a financial analyst. Call done with your summary."},
    circle: %{type: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}
  })

{:ok, result, _cantrip, _loom, _meta} =
  Cantrip.cast(cantrip, "Revenue up 14% QoQ, churn down 2 points. Summarize.")
```

With a real provider from environment variables:

```elixir
{:ok, cantrip} =
  Cantrip.new_from_env(
    identity: %{system_prompt: "Call done with the answer."},
    circle: %{type: :conversation, gates: ["done"], wards: [%{max_turns: 10}]}
  )
```

Typical provider environment:

```bash
CANTRIP_LLM_PROVIDER=openai_compatible
CANTRIP_MODEL=gpt-4.1-mini
CANTRIP_API_KEY=sk-...
CANTRIP_BASE_URL=https://api.openai.com/v1
```

Supported provider modules include OpenAI-compatible, Anthropic, Gemini,
and ReqLLM adapters.

## Core API

### `Cantrip.new/1`

Builds a reusable cantrip value from:

- `:llm` - `{module, state}`
- `:identity` - system prompt and behavior options
- `:circle` - medium, gates, and wards

Every circle must include a `done` gate and at least one truncation ward.

### `Cantrip.cast/2`

Runs a one-shot entity and stops it when the cast completes:

```elixir
{:ok, result, cantrip, loom, meta} = Cantrip.cast(cantrip, "Analyze this data")
```

### `Cantrip.summon/1` and `Cantrip.send/2`

Runs a persistent entity across multiple intents:

```elixir
{:ok, pid} = Cantrip.summon(cantrip)
{:ok, first, _, _, _} = Cantrip.send(pid, "Set up the analysis.")
{:ok, second, _, _, _} = Cantrip.send(pid, "Continue from there.")
```

### `Cantrip.cast_batch/1`

Runs child cantrips in parallel and returns results in request order:

```elixir
{:ok, results, children, looms, meta} =
  Cantrip.cast_batch([
    %{cantrip: analyst, intent: "Read chapter one."},
    %{cantrip: analyst, intent: "Read chapter two."}
  ])
```

### `Cantrip.cast_stream/2`

Returns `{stream, task}`. The stream yields `{:cantrip_event, event}`
tuples while the task runs.

## Circle

The circle is the action envelope:

```text
A = M union G - W
```

The medium is how the entity thinks. Gates are host functions exposed
across the boundary. Wards are enforced limits.

```elixir
%{
  type: :code,
  gates: ["done", "read_file", "list_dir", "search"],
  wards: [%{max_turns: 10}, %{max_depth: 2}]
}
```

Common built-in gates:

- `done`
- `echo`
- `read_file`
- `list_dir`
- `search`
- `call_entity`
- `call_entity_batch`
- `compile_and_load`

## Mediums

### Conversation

The LLM receives gates as tool definitions and responds with tool calls.
Use this for interpretation, judgment, synthesis, naming, and direct
answers.

### Code

The entity writes Elixir. Bindings persist across turns and sends.
Gates are injected as functions, and `loom` is available as data.

```elixir
data = read_file.(path: "metrics.txt")
done.("Read #{byte_size(data.result)} bytes")
```

Code-medium entities can also use the public package API:

```elixir
{:ok, child} =
  Cantrip.new(%{
    identity: %{system_prompt: "Read the provided material and summarize it."},
    circle: %{type: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}
  })

{:ok, summary, child, _loom, _meta} = Cantrip.cast(child, content)
done.(summary)
```

The default code medium evaluates unrestricted Elixir in the same BEAM.
Use deployment isolation for production, or opt into the Dune sandbox
when stronger in-VM restriction is more important than full Elixir
ergonomics.

### Bash

The entity writes shell commands. Each command runs in a fresh subprocess
from the configured cwd. Shell state does not persist, but filesystem
changes do. A command returns the final answer by printing `SUBMIT:`.

## The Familiar

The Familiar is the production RLM-facing entity. It observes a codebase,
reasons in Elixir, creates child cantrips with the public API, fans out
work with `Cantrip.cast_batch/1`, and reads prior work through its loom.

```bash
mix cantrip.familiar
mix cantrip.cast "summarize the runtime boundaries"
mix cantrip.familiar --acp
```

Workspace-scoped Familiars default to durable Mnesia-backed loom storage
where available. JSONL, DETS, memory, and auto storage can be selected
explicitly.

## Storage

```elixir
Cantrip.new(%{..., loom_storage: :memory})
Cantrip.new(%{..., loom_storage: {:jsonl, "loom.jsonl"}})
Cantrip.new(%{..., loom_storage: {:dets, "loom.dets"}})
Cantrip.new(%{..., loom_storage: {:mnesia, %{table: :cantrip_turns}}})
Cantrip.new(%{..., loom_storage: {:auto, %{dets_path: "loom.dets"}}})
```

Mnesia persistence across BEAM restarts requires a named node and a
writable Mnesia directory. See [DEPLOYMENT.md](./DEPLOYMENT.md).

## Safety

Safety is layered:

- gate root validation for filesystem gates
- credential redaction before observations reach the entity
- diagnostic redaction before protocol/debug output
- deployment isolation around unrestricted BEAM execution
- optional Dune sandbox
- hot-load wards for module/path/hash/signer/namespace policy

Root validation applies to gates. It does not constrain arbitrary
`File.*` calls made by unrestricted Elixir code. Production deployments
must account for that explicitly.

## Verification

```bash
mix verify
```

The release gate checks formatting, compiles with warnings as errors,
runs the full test suite, and runs Credo warnings/errors. Refactoring-only
Credo suggestions are cleanup debt rather than release blockers.

The suite includes a conformance runner for the shared `tests.yaml`
cases plus runtime, storage, ACP, streaming, Familiar, provider,
redaction, and code-medium tests.

## Package Status

ACP support depends on `agent_client_protocol ~> 0.1.0` from Hex. The
package surface is checked with `mix docs` and `mix hex.build`.
