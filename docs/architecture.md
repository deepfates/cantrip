# Architecture

Cantrip is an Elixir/OTP runtime for language-model entities acting through
mediums, gates, wards, and looms. It is the canonical package implementation of the Cantrip
spellbook lineage: the original ghost-library vocabulary is preserved, while
the runtime surface is ordinary Elixir.

## Core Shape

A cantrip is a reusable value. It combines:

- an LLM behaviour implementation and provider state
- an identity with system prompt and model-facing options
- a circle describing medium, gates, and wards
- optional loom storage, retry, and folding configuration

Casting a cantrip starts a one-shot entity. Summoning a cantrip starts a
supervised entity process that can receive multiple intents. The entity is what
emerges from the loop; the cantrip is the configuration that produces it.

The circle is the runtime contract:

```text
A = M union G - W
```

The medium determines the shape of thought. Gates expose host capabilities.
Wards bound runtime behavior. The loom is the durable tree left behind by the
entity's turns. The Familiar's default code medium runs Dune-restricted Elixir
in a child BEAM, with gates and child cantrip API calls resolved by the parent
runtime.

## Runtime Loop

`Cantrip.cast/3` starts a supervised `Cantrip.EntityServer` for one episode.
`Cantrip.summon/1` starts a persistent entity; `Cantrip.summon/2` starts one
and immediately runs its first intent. `Cantrip.send/3` continues it.

Each turn:

1. folds prompt context if configured
2. presents the selected medium to the LLM
3. invokes the provider through `Cantrip.ProviderCall`
4. classifies the response in `Cantrip.Turn`
5. executes through the medium
6. appends the utterance and observations to the loom
7. either terminates, truncates, or continues

Errors that belong to the entity's operating environment are observations.
They are returned to the loop as data instead of crashing the process.

## Mediums

`Cantrip.Medium.Conversation` projects gates as provider tool definitions.

`Cantrip.Medium.Code` evaluates Elixir with persistent bindings. By default,
it evaluates Dune-restricted Elixir in a child BEAM process, equivalent to
`sandbox: :port`. Add `%{port_runner: [...]}` to put that child under
deployment-level OS/container controls. `sandbox: :port_unrestricted` keeps
the child process but evaluates raw Elixir there. `sandbox: :dune` routes
through the in-process Dune evaluator. `sandbox: :unrestricted` uses the old
host-BEAM evaluator for trusted local development.

`Cantrip.Medium.Bash` executes one shell command per turn. Shell process state
does not persist; filesystem effects do.

## Composition

Composition uses the public package API, not special delegation gates.
Code-medium entities call `Cantrip.new/1`, `Cantrip.cast/3`, and
`Cantrip.cast_batch/2` directly. Parent context supplies inherited child LLM,
wards, root dependencies, cancellation, streaming, and loom grafting.

This is the RLM pattern in package form: large context lives in the medium,
subtasks run as child cantrips, and summaries return upward. Composition is
code, not a static workflow graph.

## Loom

The loom is the durable artifact of the loop. It records intents, turns,
utterances, observations, child turns, metadata, and fork lineage.

Backends:

- memory for ephemeral tests and scratch sessions
- JSONL for portable traces
- Mnesia for BEAM-native durable workspace state

Folding is a view over prompt context. When the message history grows past
a configured threshold, older turns are summarized into a compact `[Folded:
turns N..M]` marker in the LLM's input. The original turns remain in the
loom unchanged — folding shrinks what the model sees on the next call, not
what was recorded. Configure with the `:folding` option on `Cantrip.new/1`.

## Safety Posture

The controls are explicit and scoped:

- gate root validation constrains filesystem gates
- redaction scrubs observations before they reach the entity
- diagnostic redaction protects protocol/debug output
- loop wards bound turns, depth, timeouts, and selected policies
- Dune-in-port evaluation denies ambient filesystem/system/process authority
  and keeps LLM-written Elixir out of the host BEAM
- `port_runner` lets deployments put the child process inside an OS/container
  sandbox
- optional Dune routes code evaluation through an in-VM restricted evaluator
- compile/load wards scope hot-loaded modules, paths, hashes, signers, and
  namespaces

The default port sandbox protects the host BEAM and denies ambient language
capabilities. Deployment-level OS controls remain useful defense in depth for
mounts, network, CPU, memory, and user isolation.
