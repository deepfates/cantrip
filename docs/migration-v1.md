# Migrating to Cantrip v1

Cantrip `1.0.0-rc.1` makes the Elixir implementation the canonical package
surface for v1. The old learning-era spec, YAML conformance suite, example
module, and alternate language implementations are no longer part of the
shipped surface.

The project still uses the original Cantrip vocabulary: cantrip, entity,
circle, medium, gate, ward, and loom are architectural terms, not theme. What
changed in v1 is the packaging contract. The Elixir implementation is now the
installable source of truth. The code medium defaults to the port-isolated
runtime; unrestricted host-BEAM evaluation is an explicit trusted-development
escape hatch. The default port medium evaluates code through Dune inside a
child BEAM; `port_runner: [...]` is available for additional OS/container
controls.

## Provider Configuration

Use ReqLLM through `Cantrip.LLM.from_env/1`:

```elixir
{:ok, llm} = Cantrip.LLM.from_env()

{:ok, cantrip} =
  Cantrip.new(
    llm: llm,
    identity: %{system_prompt: "Call done with the answer."},
    circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 5}]}
  )
```

Removed helpers:

- the former `llm_from_env/0` helper on `Cantrip`
- the former `new_from_env/1` helper on `Cantrip`
- hand-written OpenAI-compatible, Anthropic, and Gemini adapters

## Composition

Composition now uses the public API directly.

Before:

```elixir
call_entity.(%{intent: "Summarize this file."})
```

Now:

```elixir
{:ok, child} =
  Cantrip.new(
    llm: llm,
    identity: %{system_prompt: "Summarize the input and call done."},
    circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 5}]}
  )

{:ok, summary, _child, _loom, _meta} =
  Cantrip.cast(child, file_contents)
```

For multiple children, use `Cantrip.cast_batch/2`.

Removed gates:

- `call_entity`
- `call_entity_batch`

## Filesystem Access

Use `read_file`. The old bare `read` gate was removed.

```elixir
circle: %{
  type: :code,
  gates: [
    :done,
    %{name: "read_file", dependencies: %{root: "/workspace"}}
  ],
  wards: [%{max_turns: 10}]
}
```

Filesystem gates validate paths against configured roots and fail closed when
required root dependencies are missing. This does not constrain arbitrary
`File.*` calls made by unrestricted code-medium Elixir; isolate production
deployments accordingly.

## Storage

Supported loom storage:

- `:memory`
- `{:jsonl, path}`
- `{:mnesia, opts}`

Removed storage adapters:

- DETS
- Auto

## Mix Tasks

The package task surface is now:

- `mix cantrip.cast`
- `mix cantrip.familiar`

The old example, ACP-specific, and standalone REPL tasks were removed or folded
into the Familiar task.

## Documentation as Contract

The authoritative contract is now the Elixir implementation, ExUnit suite, and
package documentation. Harvested behavior from the old conformance files lives
in native tests instead of `SPEC.md` and `tests.yaml`.
