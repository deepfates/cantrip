# Cantrip

A spellbook for summoning entities from language. Disguised as an Elixir
agent runtime.

Putting language in a loop can make it come alive. You say words, the words
change the room, the room changes you, you say different words. We call it
chanting, and it is one of the oldest tools of magic.

An agent is the same shape. The model predicts a token; put it in a loop
with an environment, and something emerges that wasn't in the instructions.
Cantrip names the parts:

- **Circle** — the environment the entity is given to act within
- **Medium** — the substrate the entity thinks in (conversation, Elixir, a shell)
- **Gates** — boundary crossings where the circle opens outward (file reads,
  child entities, hot-loaded modules)
- **Wards** — enforced runtime constraints (turn limits, recursion depth,
  medium options, hot-load policy)
- **Loom** — every turn recorded as a tree of threads, forkable and replayable
- **Entity** — what arises from the loop. You don't build it. You design the
  circle, and it emerges.

A **cantrip** is the reusable value that binds an LLM, an identity, and a
circle. When you `cast` or `summon` it, an entity appears in the loop. The
action space is the formula:

```
A = M ∪ G − W
```

## Quick Start

```bash
mix deps.get
cp .env.example .env

mix cantrip.cast "explain what a cantrip is"
```

That's a bare conversation cantrip with a `done` gate. For the full
code-medium coordinator that lives in your codebase:

```bash
mix cantrip.familiar
mix cantrip.familiar "summarize the loom storage modules"
mix cantrip.familiar --acp
```

## Workflows

The same package primitives cover several distinct shapes:

- **Workspace cantrip** — give an entity a medium, gates, wards, and a loom so
  it can work in a real environment with explicit controls.
- **Persistent entity** — summon the cantrip into an OTP process when related
  prompts should share process-owned state.
- **Child cantrip composition** — fan out work to specialized children and
  graft their results and looms back into the parent run.
- **Familiar coordinator** — use the packaged codebase-facing entity when you
  want workspace gates, code-medium reasoning, durable memory, and delegation
  assembled for you.
- **Protocol surface** — expose the same runtime through library calls, Mix
  tasks, streaming events, or stdio ACP.

### Build a Workspace Cantrip

A code-medium cantrip that inspects a workspace through scoped filesystem
gates and leaves a JSONL loom behind. The entity thinks in Elixir, uses
`list_dir`, `search`, and `read_file` as host functions, and records every
turn:

```elixir
{:ok, llm} = Cantrip.LLM.from_env()
root = File.cwd!()

{:ok, cantrip} =
  Cantrip.new(
    llm: llm,
    identity: %{
      system_prompt: """
      You are a careful codebase analyst. Inspect the workspace through the
      available gates and call done with a concise findings list.
      """
    },
    circle: %{
      type: :code,
      gates: [
        :done,
        %{name: "list_dir", dependencies: %{root: root}},
        %{name: "search", dependencies: %{root: root}},
        %{name: "read_file", dependencies: %{root: root}}
      ],
      wards: [%{max_turns: 8}, %{sandbox: :port}, %{code_eval_timeout_ms: 5_000}]
    },
    loom_storage: {:jsonl, "tmp/cantrip-analysis.jsonl"}
  )

{:ok, result, _next, loom, meta} =
  Cantrip.cast(cantrip, """
  Find the modules responsible for loom storage and summarize their
  persistence choices, including any operational risks a deployer should know.
  """)
```

Provider configuration is routed through ReqLLM:

```bash
CANTRIP_LLM_PROVIDER=openai_compatible
CANTRIP_MODEL=gpt-5-mini
CANTRIP_API_KEY=sk-...
CANTRIP_BASE_URL=https://api.openai.com/v1
```

`Cantrip.FakeLLM` scripts deterministic responses for tests.

### Keep an Entity Alive

Use `summon` when an entity should keep process-owned state across multiple
intents:

```elixir
{:ok, pid} = Cantrip.summon(cantrip)
{:ok, _first, _next, _loom, _meta} = Cantrip.send(pid, "Map the storage modules.")
{:ok, second, _next, loom, _meta} =
  Cantrip.send(pid, "Continue from there: compare JSONL and Mnesia.")
```

### Fan Out to Child Cantrips

Use ordinary cantrips as children. Results return in request order; each
child also produces a loom.

```elixir
{:ok, jsonl_reader} =
  Cantrip.new(
    llm: llm,
    identity: %{system_prompt: "Summarize the JSONL storage implementation."},
    circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 5}]}
  )

{:ok, mnesia_reader} =
  Cantrip.new(
    llm: llm,
    identity: %{system_prompt: "Summarize the Mnesia storage implementation."},
    circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 5}]}
  )

{:ok, summaries, _children, _looms, _meta} =
  Cantrip.cast_batch([
    %{cantrip: jsonl_reader, intent: "Focus on lib/cantrip/loom/storage/jsonl.ex"},
    %{cantrip: mnesia_reader, intent: "Focus on lib/cantrip/loom/storage/mnesia.ex"}
  ])
```

### Launch the Familiar

The Familiar is the batteries-included coordinator for codebase work. It
observes the workspace, reasons in Elixir, delegates to child cantrips, and
persists its loom.

```elixir
{:ok, familiar} = Cantrip.Familiar.new(llm: llm, root: File.cwd!())

{:ok, report, _next, _loom, _meta} =
  Cantrip.cast(familiar, "Inspect this repo and report the package shape.")
```

Hot-loading is opt-in. Pass `evolve: true` to include `compile_and_load`
and an exact allowlist for `Elixir.Cantrip.Hot.Tally`. Be careful what you
wish for; the Familiar is minimally warded.

## Core API

`Cantrip.new/1` builds a reusable cantrip value from an LLM tuple, identity,
circle, loom storage, retry policy, and folding options.

`Cantrip.cast/3` summons a one-shot entity for one intent:

```elixir
{:ok, result, cantrip, loom, meta} =
  Cantrip.cast(cantrip, "Analyze this data", stream_to: self())
```

`Cantrip.cast_batch/2` runs child cantrips concurrently and returns results
in request order:

```elixir
{:ok, results, children, looms, meta} =
  Cantrip.cast_batch([
    %{cantrip: analyst, intent: "Read chapter one."},
    %{cantrip: analyst, intent: "Read chapter two."}
  ])
```

`Cantrip.cast_stream/2` returns `{stream, task}` for event consumers.

`Cantrip.summon/1` and `Cantrip.send/3` keep a supervised entity process
alive across multiple intents.

`Cantrip.Loom.fork/4` replays a loom prefix and branches from a prior turn.

See [`docs/public-api.md`](./docs/public-api.md) for a task-oriented API guide.

## Mediums

The medium is the inside of the circle — what the entity thinks in.

**Conversation.** The LLM receives gates as tool definitions and responds
with structured calls. Right when the work IS speech: interpretation,
judgment, naming.

**Code.** The entity writes Elixir. Bindings persist across turns. Gates
are injected as functions; `loom` is available as data. Right when the work
is composition: gathering pieces, transforming them, aggregating, fanning
out. Children are constructed through the public package API:

```elixir
data = read_file.(path: "metrics.txt")
done.("Read #{byte_size(data)} bytes")
```

Code-medium cantrips use the safe port boundary by default: LLM-written Elixir
is evaluated by Dune inside a child BEAM process, while gates, child cantrip
API calls, stdio, and hot-loading are resolved through explicit parent/child
protocol messages. Use `%{sandbox: :port}` when you want that default boundary
to be explicit in a circle. Use `sandbox: :port_unrestricted` only when you
explicitly want raw Elixir in the child process, `sandbox: :dune` when you
want in-process language restriction with a deliberately smaller binding
surface (see [docs/port-isolated-runtime.md](./docs/port-isolated-runtime.md)
for the divergence — entity prompts need to match the variant in use), or
`sandbox: :unrestricted` only for trusted local development in the host BEAM.
Child-origin atoms outside Cantrip's wire vocabulary cross the port boundary
as strings, which keeps hot-loaded child code from forcing new atoms into the
parent BEAM.

**Bash.** The entity writes shell commands. Each command runs in a fresh
subprocess from the configured cwd. Shell state does not persist; filesystem
changes do. A command returns the final answer by printing `SUBMIT:`.

## Gates

Built-in gates close over construction-time dependencies and produce
observations the entity reads as data:

- `done(answer)` — terminate with the final answer
- `echo(text)` — visible observation
- `read_file(%{path})` — read a file under `:root`
- `list_dir(%{path})` — list a directory under `:root`
- `search(%{pattern, path})` — regex search returning `%{path, line, text}`
  matches
- `mix(%{task, args})` — run an allowlisted Mix task under `:root`
- `compile_and_load(%{module, source})` — compile and hot-load a module
  (opt-in via `evolve: true` on the Familiar)

Errors are observations. A failed gate call returns to the entity as data
so the next turn can adapt. Error as steering.

## Storage

The loom is the durable record of every turn the entity and its children
have taken. Three backends:

```elixir
base = [
  llm: llm,
  identity: %{system_prompt: "..."},
  circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 5}]}
]

Cantrip.new(Keyword.put(base, :loom_storage, :memory))
Cantrip.new(Keyword.put(base, :loom_storage, {:jsonl, "loom.jsonl"}))
Cantrip.new(Keyword.put(base, :loom_storage, {:mnesia, table: :cantrip_turns}))
```

Mnesia persistence across BEAM restarts requires a named node and a writable
Mnesia directory. See [DEPLOYMENT.md](./DEPLOYMENT.md).

## Safety

The default code-medium boundary is two-layered. Dune denies ambient `File.*`,
`System.*`, `Process.*`, `spawn`, and similar capabilities inside the child;
the port boundary keeps LLM-written code, hot-loaded modules, and spawned child
work out of the host BEAM. Gate calls, hot-load validation, child cantrip
construction, casting, loom grafting, telemetry, and provider access stay in
the parent runtime. Timeouts close and kill the child process.

This is a real default sandbox for the code medium, not merely documentation.
For stricter operating-system policy — filesystem mounts, network egress,
CPU/memory quotas, and user isolation — add `:port_runner` or run the host in a
constrained container. The raw child-BEAM evaluator is `sandbox:
:port_unrestricted`; the old host-BEAM evaluator is `sandbox: :unrestricted`.
See [DEPLOYMENT.md](./DEPLOYMENT.md) for the full posture.

## Where to go next

- `notebooks/cantrip_demo.livemd` — the runnable grimoire, with rendered loom
  tables
- [`docs/public-api.md`](./docs/public-api.md) — task-oriented API guide
- [`docs/architecture.md`](./docs/architecture.md) — how the modules fit
- [`DEPLOYMENT.md`](./DEPLOYMENT.md) — current deployment posture
- [`docs/migration-v1.md`](./docs/migration-v1.md) — moving from pre-v1
- [`docs/port-isolated-runtime.md`](./docs/port-isolated-runtime.md) — the
  port-isolated code-medium boundary
- [Cantrip bibliography](https://deepfates.com/cantrip-bibliography) — the
  intellectual lineage

## Package status

This package is `1.0.0`. ACP support depends on
`agent_client_protocol ~> 0.1.0` from Hex. The package surface is checked with
`mix docs` and `mix hex.build`.
