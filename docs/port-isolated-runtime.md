# Port-Isolated Code Medium

The port code medium is Cantrip's default sandbox for LLM-written Elixir. It
preserves the important part of the code medium — the entity still writes
Elixir with persistent bindings — while evaluating that code through Dune in a
child BEAM process.

The default `sandbox: :port` path is deliberately not raw child Elixir. Dune
denies ambient filesystem, system command, process, spawn, node, and similar
capabilities. The port boundary keeps the evaluator, hot-loaded modules, and
child-spawned work out of the host BEAM. Gates and package composition cross
the boundary only through explicit RPC frames.

## Boundary

The parent BEAM owns:

- the public Cantrip API and entity supervision
- provider calls
- gate registration and execution
- filesystem root validation
- credential redaction
- loom storage and child-turn grafting
- telemetry and streaming events
- hot-load policy validation

The child BEAM owns:

- Dune-restricted evaluation of LLM-written Elixir
- persistent code-medium bindings for the session
- modules hot-loaded through `compile_and_load`
- raw processes spawned only when using the explicit `:port_unrestricted`
  escape hatch

On evaluation timeout, the parent closes and kills the child OS process. That
ends the child session and any processes spawned inside it.

## Child Runner

By default, Cantrip starts the child directly:

```text
elixir -pa ... -e "Cantrip.Medium.Code.PortChild.main()"
```

Set `%{port_runner: [executable, arg1, ...]}` in the circle wards, or pass
`port_runner: [...]` to `Cantrip.Familiar.new/1`, to prepend an OS/container
runner before that command. This is optional defense in depth for deployments
that also want mount, network, CPU, memory, or user controls around the child
process.

Cantrip tests that the configured runner is used. Cantrip does not verify the
security properties of an arbitrary runner; that belongs to the deployment.

## Protocol

Parent and child communicate over an Erlang port using length-prefixed
Erlang external terms. The main frames are:

```elixir
{:init, binding}
{:ready, child_pid}
{:eval, ref, code, env}
{:gate_call, ref, gate_name, args}
{:gate_result, ref, observation}
{:compile_request, ref, args}
{:compile_allowed, ref, payload}
{:compile_denied, ref, observation}
{:api_call, ref, function, args}
{:api_result, ref, reply}
{:eval_result, ref, binding, value, terminated?, captured_output}
{:eval_error, ref, binding, reason, captured_output}
```

The child receives gate closures. Calling `read_file.(...)`, `search.(...)`,
or `done.(...)` sends a request to the parent and returns the parent result to
the child code.

## Public API Proxies

Inside the child, ordinary calls to:

- `Cantrip.new/1`
- `Cantrip.cast/2`
- `Cantrip.cast/3`
- `Cantrip.cast_batch/1`
- `Cantrip.cast_batch/2`

are rewritten to injected proxy closures. The parent constructs and runs the
children, applies parent-context inheritance, grafts child turns into the
loom, and sends serializable results back to the child. The entity can write
normal Cantrip composition code without receiving authority over the parent
BEAM.

## Hot Loading

When `compile_and_load` is present in the circle, the child can request a hot
load. The parent validates the request against compile wards:

- allowed module names or namespaces
- allowed compile paths
- allowed source hashes
- allowed signer keys and signatures

If validation passes, the child compiles and loads the module in the child
BEAM only. The parent framework VM is not modified. In the safe port evaluator,
newly loaded modules are added to that child session's Dune allowlist, so the
same turn can call the module after a successful `compile_and_load`.

## Escape Hatches

`sandbox: :port_unrestricted` keeps the child process and timeout cleanup but
evaluates raw Elixir in that child. It exists for trusted experiments and for
testing process-kill behavior. It is not the Familiar default.

`sandbox: :unrestricted` uses the legacy host-BEAM evaluator. It is for trusted
local development only.

## Remaining Deployment Responsibility

The default port sandbox denies ambient language capabilities and protects the
host BEAM. If a deployment also needs operating-system isolation — mount
namespaces, network egress policy, CPU/memory quotas, or a distinct OS user —
apply those limits with `:port_runner` or around the whole host process.
