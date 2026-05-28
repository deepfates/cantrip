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
through the in-process Dune evaluator — a deliberately smaller-surface
variant of the code medium (see `docs/port-isolated-runtime.md` "Dune
Variant"); entity prompts need to fit that surface. `sandbox: :unrestricted`
uses the old host-BEAM evaluator for trusted local development.

`Cantrip.Medium.Bash` executes one shell command per turn. Shell process state
does not persist; filesystem effects do.

ACP stdio embedding must start the `:cantrip` application before sessions
create event bridges. `Cantrip.ACP.Server.run/1` does this for the packaged
entrypoint; custom embedders should either call `Application.ensure_all_started(:cantrip)`
or supervise `Cantrip.ACP.EventBridgeSupervisor` themselves.

ACP request metadata is also the production trace-correlation boundary. The
handler accepts `_meta.trace_id` or `_meta.cantrip_trace_id` on `session/new`
and `session/prompt`; the Familiar runtime carries that value into
`Cantrip.summon/3` / `Cantrip.send/3` so telemetry emitted by the entity can be
joined to an external request, job, or editor operation. Without that metadata,
the entity mints its own trace ID. `_meta` is not a Familiar configuration
channel: LLM selection, loom paths, turn budgets, and other runtime controls
come from server/runtime configuration, not from editor-supplied request
metadata.

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
- child-BEAM telemetry events are forwarded over the port protocol and
  re-emitted by the parent with the same trace context
- `port_runner` lets deployments put the child process inside an OS/container
  sandbox
- optional Dune routes code evaluation through an in-VM restricted evaluator
- compile/load wards scope hot-loaded modules (exact `allow_compile_modules`
  list), paths, hashes, and signers; framework modules under `Elixir.Cantrip.*`
  (except `Elixir.Cantrip.Hot.*`) are rejected even when explicitly allowlisted

The default port sandbox protects the host BEAM and denies ambient language
capabilities. Deployment-level OS controls remain useful defense in depth for
mounts, network, CPU, memory, and user isolation.

### Struct conventions for credential-bearing data

Any struct that holds credential-shaped fields — API keys, bearer tokens,
authorization headers, signed cookies — must declare `@derive {Inspect, only:
[<non-secret-fields>]}` (or `@derive {Inspect, except: [<secret-fields>]}`).
This prevents accidental leak via default `inspect/1` in IEx sessions, error
output, logger calls, or debug dumps. The safe formatting helpers cover the
runtime boundary error surfaces; the `@derive Inspect` convention covers the
construction-and-debug surface.

Current durable structs do not hold credentials directly — `:llm_state` on the
top-level `%Cantrip{}` is a plain map carrying provider state including
`:api_key`, and downstream code is expected to either redact at the boundary
via the safe formatting helpers or to not log raw `:llm_state`. Future structs that
directly hold credentials must adopt the convention above.

## Process Inventory

Every process kind cantrip starts, plus its owner, restart strategy, and
shutdown semantics. Reference this section when adding a new process.

| Process kind | Started by | Owner | Crash-restart | Shutdown |
|---|---|---|---|---|
| `Cantrip.EntityServer` (GenServer) | `Cantrip.cast/3`, `Cantrip.summon/1` via `DynamicSupervisor.start_child` | entity dynamic supervisor | `:temporary` (no auto-restart; caller gets error) | default GenServer 5s; `terminate/2` sends `:stop` to runner |
| Per-entity runner Task | `EntityServer.start_runner/0` (`lib/cantrip/entity_server.ex:240`) | `Cantrip.EntityTaskSupervisor` (Task.Supervisor) | `:temporary` (Task.Supervisor default) | `:brutal_kill` 5s on app shutdown; in-progress episodes interrupted |
| Code-medium child BEAM | `Cantrip.Medium.Code.Port.start_child` (line 109) | not supervised; linked to eval context | N/A (process-level) | on eval timeout or parent crash: implicit exit via port boundary |
| Port-child protocol loop | `spawn_link` in `port_child.ex:138` | linked to parent (child-side bootstrap) | N/A (linked) | parent exit propagates crash via link |
| ACP EventBridge loop | `Task.Supervisor.start_child/2` in `acp/event_bridge.ex` | `Cantrip.ACP.EventBridgeSupervisor` | `:temporary` (Task.Supervisor default) | `:DOWN` from monitored owner OR explicit `:stop` message |
| `Cantrip.cast_stream/2` task | `Task.async` (`lib/cantrip.ex:641`) | unlinked; caller drains via Stream | N/A (unlinked) | implicit when stream resource closes |
| `Cantrip.cast_batch/2` children | `Task.async_stream` (`lib/cantrip.ex:510`) | Task.async_stream context; bounded by `max_concurrent_children` ward | N/A (bounded enumeration) | killed on `max_concurrency` overflow or timeout |
| Code/Bash medium eval Tasks | `Task.async` in `medium/code.ex:163`, `medium/bash.ex:119` | unlinked; timeout-guarded by `code_eval_timeout_ms` / similar ward | N/A (unlinked) | `Task.yield` + `Task.shutdown(:brutal_kill)` on timeout |

This inventory is the contract; any new long-lived or supervised process must
extend this table.
