# Deploying the Familiar

The Familiar is a long-lived BEAM-native entity. It reasons in Elixir,
spawns other entities at runtime, persists its loom across summons,
and can hot-load new code into its own runtime. This document is about running
it responsibly in production.

Cantrip `1.0.0-rc.1` makes the Familiar's default code medium a safe port
evaluator: LLM-written Elixir is evaluated by Dune inside a child BEAM process
while the parent BEAM owns gates, child cantrip orchestration, loom grafting,
telemetry, provider access, and hot-load policy.

## The runtime shape

The parent runtime lives in the application BEAM: cantrip framework, loom
storage, LLM client, gates, telemetry, and Familiar entry point (ACP or
single-shot CLI). The entity's code-medium Elixir runs in a child BEAM reached
through an Erlang port.

That split is the v1 boundary. The entity gets Elixir as its medium, but Dune
denies ambient filesystem/system/process authority and boundary crossings are
parent-mediated: gates are RPC handles, `Cantrip.new/1`, `Cantrip.cast/2`, and
`Cantrip.cast_batch/1` are proxied to the parent, and `compile_and_load` is
validated by the parent before compiling inside the child runtime.

## Safety Posture

The default controls are structural at the BEAM boundary:

- gate validation controls parent-mediated gate calls
- redaction controls observations before they return to the entity/model
- wards bound loop structure and selected runtime policies
- Dune-in-port evaluation denies ambient language capabilities and keeps
  LLM-written Elixir out of the host BEAM
- optional deployment isolation controls the child/host operating-system
  process boundary

### 1. Gate root validation

Filesystem-touching gates (`read_file`, `list_dir`, `search`) accept a
`root` dependency at construction time. Paths the entity passes get
validated against that root before the gate runs. A path that escapes
the root surfaces as an error observation, not a successful read.

Filesystem gates that require `root` fail closed when `root` is missing.
The old bare `read` gate was removed; use `read_file`.

This is configured by passing `:root` to `Cantrip.Familiar.new/1`:

```elixir
Cantrip.Familiar.new(llm: llm, root: "/path/to/workspace")
```

The Familiar's `list_dir` and `search` gates inherit this root. When the
Familiar constructs child cantrips with `Cantrip.new/1`, parent context
merges the parent's dependencies into the child's gates, so a child given
`gates: ["read_file", "done"]` automatically gets the same root.

### 2. Credential redaction

Every gate observation result passes through `Cantrip.Redact.scan/1`
before reaching the entity. Pattern-based scrubbing of common
credential shapes:

- `sk-...` (OpenAI-shaped)
- `sk-ant-...` (Anthropic-shaped)
- `AIza...` (Google)
- `AKIA...` / `ASIA...` (AWS access keys)
- `Bearer <token>` headers
- Generic env-style `*KEY|SECRET|TOKEN|PASSWORD=...` assignments

Recursive over strings, lists, and maps so list_dir / search results
stay safe even if a filename or matched line carries a secret.
Non-binary results pass through untouched.

Defense in depth: even when a path read succeeds (e.g., the entity
reads `.env` because it's inside the configured root), the credential
*bodies* are replaced with `[REDACTED]` before the entity (and the
human watching) ever sees them.

### 3. Port isolation and process cleanup

The Familiar defaults to `%{sandbox: :port}`. The child BEAM is launched
through an Erlang port with a length-prefixed Erlang-term protocol. The parent
sends eval requests; the child evaluates them through Dune; gate/API/stdout
and compile requests cross the protocol explicitly. On timeout, the parent
closes and kills the child OS process.

Hot-loading with `evolve: true` also stays inside the child. The parent
validates `compile_and_load` wards (namespace/path/hash/signer policy), then
the child compiles and loads the allowed module in its own runtime, not in the
framework VM.

This is the default sandbox: Dune denies ambient `File.*`, `System.*`,
`Process.*`, `spawn`, node, and similar calls, while the port boundary protects
the host BEAM.

### 4. Child process containment

The child BEAM process still runs somewhere. The default evaluator denies
ambient language access to filesystem/system/process capabilities, but
operating-system isolation controls what the child process could reach if a
bug, dependency issue, NIF, VM issue, or explicit `:port_unrestricted` escape
hatch is introduced.

For production, configure a child runner:

```elixir
Cantrip.Familiar.new(
  llm: llm,
  root: "/srv/workspace",
  port_runner: ["/usr/local/bin/cantrip-child-sandbox"]
)
```

Cantrip prepends that runner before the child `elixir ...` command. The runner
can be a wrapper script around Docker, systemd-nspawn, an OCI runtime,
sandbox-exec, firejail, nsjail, or whatever your platform standardizes on.
Mount only the directories the Familiar should reach, drop OS capabilities the
process doesn't need, set CPU/memory limits, and disable network egress unless
the child genuinely needs it.

If your deployment already runs the entire Cantrip host inside an equally
constrained container, a separate `:port_runner` may be redundant. The
important claim is concrete containment somewhere, not the name of the tool.

For development: run from an environment you're willing for the entity to
reach. Credential redaction means an accidental `.env` observation is scrubbed
before it reaches the model, but it does not prevent the read itself. If you
need `File.read!("/etc/passwd")` or network egress to be impossible, run the
child or host BEAM inside an OS/container boundary that makes it impossible.

These two layers compose: redaction handles credentials wherever they
land; deployment isolation handles file paths that shouldn't be
reachable at all.

### 5. Alternate evaluators

`Cantrip.Familiar.new/1` accepts `sandbox: :dune`. This routes the code medium through
`Cantrip.Medium.Code.Dune`, which restricts language-level
`File.*`, `System.*`, `Process.*`, `spawn`, and `Code.*` (loading)
calls.

Cost: Dune also restricts some in-medium operations (`binding/0`,
`try/1`, `Code.ensure_loaded?/1`). The Familiar's prompt teaches
`binding()` introspection and pattern matching with `try/rescue`
fallback as native; under `:dune`, those teachings work less well,
and the entity has to fall back to "just reference variables by name"
and "errors land as observations the next turn sees."

Use `:dune` deliberately when you want in-process restriction without the child
BEAM boundary. `sandbox: :port_unrestricted` keeps the child process but
evaluates raw Elixir there; it is for trusted experiments and process cleanup
tests. `sandbox: :unrestricted` restores the old host-BEAM evaluator for
trusted local development only.

## Loom backends

The loom is the durable record of every turn the Familiar and its
children have ever taken. Three backends:

| Backend | Strengths | Use case |
| --- | --- | --- |
| **Mnesia** (default for workspace-scoped Familiars) | BEAM-native, transactional, queryable, distributable across nodes | Production |
| **JSONL** | Portable, exportable, human-readable | Development, sharing traces, off-BEAM consumers |
| **In-memory** (default with no `root`) | Fast, ephemeral | Tests, scratch sessions |

Selection by `Cantrip.Familiar.new/1` options:

```elixir
# Default: workspace-scoped Mnesia table derived from root
Cantrip.Familiar.new(llm: llm, root: "/path/to/workspace")

# Explicit JSONL for exportable traces
Cantrip.Familiar.new(llm: llm, root: "/path/to/workspace",
                     loom_path: "/var/log/cantrip/my_familiar.jsonl")

# Explicit Mnesia table
Cantrip.Familiar.new(llm: llm, root: "/path/to/workspace",
                     loom_storage: {:mnesia, [table: :my_table]})

# Ephemeral
Cantrip.Familiar.new(llm: llm)
```

Mnesia's table name is derived from the workspace root (a sanitized
basename plus a short hash of the full path), so multiple summons
against the same workspace converge on the same loom; distinct
workspaces don't collide.

## Wards: bounding the loop

Default wards on the Familiar's circle:

| Ward | Default | Purpose |
| --- | --- | --- |
| `max_turns` | 20 | Cap on iterations per cast |
| `max_depth` | 3 | Cap on recursive child spawning |
| `code_eval_timeout_ms` | 120,000 (2 min) | Per-turn time bound |
| `allow_compile_namespaces` | only when `evolve: true` | Hot-reload restricted to a sub-namespace |

Tune per deployment. Long-running workflows may want higher
`max_turns`; cost-sensitive deployments may want lower
`code_eval_timeout_ms`. The Familiar's prompt does not need to know
these numbers — the wards are enforced by the circle, not by the
entity.

## Hot reload (self-modification)

`compile_and_load` is opt-in for the Familiar. Pass `evolve: true` to include
the gate and scope it to the `Cantrip.Hot.*` namespace. The entity can then
write new Elixir modules into that subtree and hot-load them into its child
BEAM session. It cannot redefine `Cantrip.Familiar`, `Cantrip.Gate`, or any
other framework module in the parent runtime — the parent validates the
namespace boundary before the child compiles.

This is the entity's evolutionary surface. Combined with the BEAM's
hot-code-loading semantics (old version stays loaded for active
processes; new version takes over for new calls) and port-session restart on
timeout/crash, the Familiar can try a change and roll back by losing only the
child runtime session.

Deployments that don't want hot reload should leave `evolve` unset. Custom
circles built with `Cantrip.new/1` can still opt into `compile_and_load`
explicitly when that is the right boundary.

## Recommended production posture

```elixir
Cantrip.Familiar.new(
  llm: llm,
  root: workspace_root,
  # Mnesia loom inferred from root; transactional, queryable
  max_turns: 50,
  # Heavier wards for long-running production work
  child_llm: cheaper_llm_for_simple_subtasks
)
```

Plus:

- Container-isolated BEAM process; only `workspace_root` and the
  cantrip framework code mounted in.
- Credential redaction is always on; nothing to configure.
- `:telemetry` event handlers wired to your observability stack
  (every gate call, every turn, every fold emits events).
- Mnesia's persistence directory mounted to durable storage.

Optional:

- `sandbox: :dune` if the BEAM is shared with untrusted tenants.
- `sandbox: :unrestricted` only for trusted local development.
- `evolve: true` only when hot-load self-extension is part of the deployment.
- Mnesia replication across cluster nodes if you're running
  distributed.

## What the framework does NOT provide

Honest list:

- **Network isolation.** Outbound network calls available to the child or
  parent process go wherever your DNS resolves. If you need egress filtering,
  that's a deployment-level firewall/container concern.
- **Resource accounting per tenant.** `max_turns` is a per-cast bound,
  not a per-tenant budget. Multi-tenant deployments need their own
  accounting layer.
- **Cross-restart entity state beyond the loom.** The Familiar's
  ephemeral in-process state (variable bindings outside the loom)
  does not survive a BEAM restart. The loom does. Long-running
  state belongs in the loom.

These are deliberate scope boundaries, not bugs.
