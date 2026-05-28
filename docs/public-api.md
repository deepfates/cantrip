# Public API Guide

This guide describes the package surface intended for application code.
Cantrip keeps the original vocabulary deliberately: a cantrip is a reusable
value, an entity is the running process or episode it produces, a circle is the
configured environment, and the loom is the durable turn tree.

## Common Workflows

The public API is organized around five distinct workflows:

- **Workspace cantrip** - assemble an LLM, identity, medium, gates, wards, and
  loom storage with `Cantrip.new/1`, then run it with `Cantrip.cast/3`.
- **Persistent entity** - keep a supervised process alive across related
  prompts with `Cantrip.summon/1` and `Cantrip.send/3`.
- **Child composition** - delegate work to specialized cantrips with
  `Cantrip.cast/3` or `Cantrip.cast_batch/2`.
- **Familiar coordinator** - launch `Cantrip.Familiar` when you want the
  packaged codebase-facing circle instead of assembling workspace gates,
  code-medium reasoning, storage, and delegation yourself.
- **Runtime integration** - stream events, persist looms, run Mix tasks, or
  expose ACP without changing the cantrip shape.

## Build a Cantrip

```elixir
{:ok, llm} = Cantrip.LLM.from_env()

{:ok, cantrip} =
  Cantrip.new(
    llm: llm,
    identity: %{system_prompt: "Call done with the final answer."},
    circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 8}]}
  )
```

`Cantrip.new/1` accepts keyword lists or maps and returns a reusable cantrip
value. The important fields are:

- `:llm` - `{module, state}` implementing `Cantrip.LLM`.
- `:identity` - system prompt and model-facing identity options.
- `:circle` - medium, gates, and wards.
- `:loom_storage` - `:memory`, `{:jsonl, path}`, or `{:mnesia, opts}`.
- `:child_llm` - optional cheaper or specialized LLM inherited by child cantrips.
- `:retry` - provider retry policy.
- `:folding` - prompt-context folding options.

## Run One Episode

```elixir
{:ok, result, next_cantrip, loom, meta} =
  Cantrip.cast(cantrip, "Summarize this incident report.")
```

`result` is the value returned by `done`. `next_cantrip` carries reusable
runtime configuration, `loom` is the durable turn tree, and `meta` describes
termination or truncation.

Use `Cantrip.cast_stream/2` when consumers need runtime events while the
episode is executing.

## Keep an Entity Alive

```elixir
{:ok, pid} = Cantrip.summon(cantrip)
{:ok, first, _next, _loom, _meta} = Cantrip.send(pid, "Load the dataset.")
{:ok, second, _next, _loom, _meta} = Cantrip.send(pid, "Analyze the dataset.")
```

Persistent entities are supervised processes. They keep process-owned state
across sends. In the code medium, bindings and message history remain
available to later episodes.

## Compose Work

Composition uses the same public API from inside or outside the code medium.
Outside a parent code-medium turn, pass an `llm` explicitly. Inside a parent
turn, children can inherit the parent context's child LLM.

```elixir
{:ok, child} =
  Cantrip.new(
    llm: llm,
    identity: %{system_prompt: "Read the material and return a compact summary."},
    circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 5}]}
  )

{:ok, summary, _child, _loom, _meta} =
  Cantrip.cast(child, document_text)
```

For fan-out:

```elixir
{:ok, summaries, _children, _looms, _meta} =
  Cantrip.cast_batch([
    %{cantrip: child, intent: "Summarize chapter one."},
    %{cantrip: child, intent: "Summarize chapter two."}
  ])
```

When called from a parent code-medium turn, child results are returned upward
and child turns are grafted into the parent loom.

## Choose a Medium

Conversation medium:

```elixir
circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 5}]}
```

Code medium:

```elixir
circle: %{
  type: :code,
  gates: [:done, :read_file],
  wards: [%{max_turns: 10}, %{sandbox: :port}]
}
```

Bash medium:

```elixir
circle: %{type: :bash, gates: [:done], wards: [%{max_turns: 5}]}
```

Code-medium circles default to the port sandbox when no sandbox ward is
present. `%{sandbox: :port}` makes that boundary explicit. It evaluates
Dune-restricted Elixir in a child BEAM process while gates, child cantrip API
calls, stdio, and hot-loading are resolved through the parent runtime. The
Familiar uses this boundary by default. Child-origin atoms that are not part of
Cantrip's wire vocabulary cross this boundary as strings, so hot-loaded child
code cannot force new atoms into the parent BEAM.

Use `%{port_runner: [...]}` or `Cantrip.Familiar.new(port_runner: [...])` when
you also want deployment-level OS/container controls. `sandbox:
:port_unrestricted` keeps the child process but evaluates raw Elixir there.
`sandbox: :dune` is available when in-process restrictions are the right
tradeoff — it is a deliberately smaller-surface variant of the code medium
(see `docs/port-isolated-runtime.md` "Dune Variant"); entity prompts need
to match that surface. `sandbox: :unrestricted` is the trusted host-BEAM
evaluator escape hatch.

## Configure Gates and Wards

Built-in gates are `done`, `echo`, `read_file`, `list_dir`, `search`, `mix`,
and `compile_and_load`. Filesystem and Mix gates require root dependencies in
production contexts; the Familiar wires these from its `:root` option. The
Familiar only includes `compile_and_load` when constructed with `evolve: true`.

Wards are maps. Common wards include:

- `%{max_turns: n}`
- `%{allow_mix_tasks: ["compile", "test"]}`
- `%{mix_timeout_ms: 60_000}`
- `%{max_output_bytes: 50_000}`
- `%{max_depth: n}`
- `%{port_runner: [executable, arg1, ...]}`
- `%{max_concurrent_children: n}`
- `%{code_eval_timeout_ms: n}`
- `%{allow_compile_modules: modules}`
- `%{allow_compile_paths: paths}`
- `%{allow_compile_signers: signers}`

`compile_and_load` accepts exact module allowlists via `allow_compile_modules`.
Deprecated `allow_compile_namespaces` wards are rejected loudly, and framework
module names are not hot-loadable.

Gate failures are observations. They are returned to the entity as data so the
next turn can adapt.

## Persist the Loom

```elixir
base = [
  llm: llm,
  identity: %{system_prompt: "Call done with the final answer."},
  circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 8}]}
]

Cantrip.new(Keyword.put(base, :loom_storage, :memory))
Cantrip.new(Keyword.put(base, :loom_storage, {:jsonl, "loom.jsonl"}))
Cantrip.new(Keyword.put(base, :loom_storage, {:mnesia, table: :cantrip_turns}))
```

Use JSONL for portable traces and Mnesia for BEAM-native durable workspace
state. Folding changes prompt context only; it does not delete loom records.
