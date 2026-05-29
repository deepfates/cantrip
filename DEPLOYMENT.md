# Deploying the Familiar

The Familiar is a long-lived BEAM-native entity. It reasons in Elixir,
spawns other entities at runtime, persists its loom across summons,
and can hot-load new code into its own runtime. This document is about running
it responsibly in production.

The Familiar's default code medium is trusted and operator-local:
LLM-written Elixir runs in the host BEAM with ordinary Elixir affordances.
That makes the prompt's native introspection guidance true: `binding/0`,
`Code.fetch_docs/1`, direct variable reference, `loom.turns`, and public
Cantrip API calls all work in the environment the Familiar inhabits.

Use the port or Dune sandboxes deliberately for hosted or multi-tenant
audiences. In those modes, LLM-written Elixir is evaluated under a narrower
surface while the parent BEAM owns gates, child cantrip orchestration, loom
grafting, telemetry, provider access, and hot-load policy.

## The runtime shape

The parent runtime lives in the application BEAM: cantrip framework, loom
storage, LLM client, gates, telemetry, and Familiar entry point (ACP or
single-shot CLI). By default, the Familiar's code-medium Elixir also runs in
that BEAM. This is the local coding-companion posture: the operator summoned
the entity into their own workspace and can kill the BEAM/process if needed.

When you choose `sandbox: :port`, the entity's code-medium Elixir instead
runs in a child BEAM reached through an Erlang port. Dune denies ambient
filesystem/system/process authority and boundary crossings are
parent-mediated: gates are RPC handles, `Cantrip.new/1`, `Cantrip.cast/2`, and
`Cantrip.cast_batch/1` are proxied to the parent, and `compile_and_load` is
validated by the parent before compiling inside the child runtime.

## Safety Posture

The default controls are structural at the Cantrip runtime boundary:

- gate validation controls parent-mediated gate calls
- redaction controls observations before they return to the entity/model
- wards bound loop structure and selected runtime policies
- the operator-local host process is the trust boundary for the default
  Familiar
- optional `:port`, `:dune`, and deployment isolation modes narrow the
  language or process boundary for hosted/multi-tenant use cases

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

Every gate observation result passes through the internal redaction boundary
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

### 3. Trusted local evaluator

The Familiar defaults to `%{sandbox: :unrestricted}`. LLM-written Elixir runs
in the host BEAM because the Familiar is an operator-local coding companion:
it is summoned into a workspace by the person responsible for that process.
This default matches the Familiar's prompt and code-medium teaching. Native
Elixir affordances such as `binding/0`, `try/rescue`, `Code.fetch_docs/1`,
ordinary module calls, and direct access to persistent code bindings are
available.

The runtime still enforces Cantrip-level constraints: gate root validation,
redaction, loop wards, child-depth and child-ward composition, Mix allowlists,
hot-load allowlists, and eval timeouts. These are runtime controls, not a
language sandbox.

Use this default only where the operator is willing to let the Familiar run
Elixir in the same trust domain as the host process. If you need LLM-written
Elixir to be unable to call ambient host APIs, choose an alternate evaluator
below.

### 4. Port isolation and process cleanup

With `sandbox: :port`, the child BEAM is launched through an Erlang port with
a length-prefixed Erlang-term protocol. The parent sends eval requests; the
child evaluates them through Dune; gate/API/stdout and compile requests cross
the protocol explicitly. On timeout, the parent closes and kills the child OS
process.

Hot-loading with `evolve: true` also stays inside the child. The parent
validates `compile_and_load` wards (exact module names, path, hash, and signer
policy), then the child compiles and loads the allowed module in its own
runtime, not in the framework VM.

This sandbox denies ambient `File.*`, `System.*`, `Process.*`, `spawn`, node,
and similar calls, while the port boundary protects the host BEAM. It is the
right starting point for hosted or multi-tenant preassemblies whose prompts
are written for the narrower Dune surface.

### 5. Child process containment

The child BEAM process still runs somewhere when you choose a port sandbox.
The port evaluator denies ambient language access to filesystem/system/process
capabilities, but operating-system isolation controls what the child process
could reach if a bug, dependency issue, NIF, VM issue, or explicit
`:port_unrestricted` escape hatch is introduced.

For production, configure a child runner:

```elixir
Cantrip.Familiar.new(
  llm: llm,
  root: "/srv/workspace",
  sandbox: :port,
  port_runner: ["/usr/local/bin/cantrip-child-sandbox"]
)
```

Cantrip prepends that runner before the child `elixir ...` command. The runner
can be a wrapper script around Docker, systemd-nspawn, an OCI runtime,
sandbox-exec, firejail, nsjail, or whatever your platform standardizes on.
Mount only the directories the Familiar should reach, drop OS capabilities the
process doesn't need, set CPU/memory limits, and disable network egress unless
the child genuinely needs it.

Passing `:port_runner` without an explicit `:sandbox` also selects `:port`,
so existing runner-based deployments keep using the child process boundary.

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

### 6. Alternate evaluators

`Cantrip.Familiar.new/1` accepts `sandbox: :dune`. This routes the code medium
through the in-process Dune evaluator, which restricts language-level
`File.*`, `System.*`, `Process.*`, `spawn`, and `Code.*` calls.

Cost: Dune also restricts some in-medium operations (`binding/0`,
`try/1`, `Code.ensure_loaded?/1`). The Familiar's prompt teaches
`binding()` introspection and pattern matching with `try/rescue`
fallback as native; under `:dune`, those teachings work less well,
and the entity has to fall back to "just reference variables by name"
and "errors land as observations the next turn sees."

Use `:dune` deliberately when you want in-process restriction without the child
BEAM boundary. `sandbox: :port_unrestricted` keeps the child process but
evaluates raw Elixir there; it is for trusted experiments and process cleanup
tests. `sandbox: :unrestricted` is the default trusted host-BEAM evaluator for
operator-local Familiars.

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

Workspace-scoped Mnesia uses a named BEAM node. The launcher persists that
node's distributed-Erlang cookie at `.cantrip/cookie` with mode `0600`. Cantrip
generates cookies in the format `cantrip_<48 lowercase hex chars>` so it can
reuse them without creating atoms from arbitrary file content. If the cookie
file exists but does not match that format, startup fails and leaves the file
unchanged. Delete `.cantrip/cookie` explicitly when you want Cantrip to rotate
the workspace cookie.

## Wards: bounding the loop

Default wards on the Familiar's circle:

| Ward | Default | Purpose |
| --- | --- | --- |
| `max_turns` | 20 | Cap on iterations per cast |
| `max_depth` | 3 | Cap on recursive child spawning |
| `code_eval_timeout_ms` | 120,000 (2 min) | Per-turn time bound |
| `allow_compile_modules` | only when `evolve: true` | Hot-reload restricted to exact module names |

Tune per deployment. Long-running workflows may want higher
`max_turns`; cost-sensitive deployments may want lower
`code_eval_timeout_ms`. The Familiar's prompt does not need to know
these numbers — the wards are enforced by the circle, not by the
entity.

## Hot reload (self-modification)

`compile_and_load` is opt-in for the Familiar. Pass `evolve: true` to include
the gate and scope it to the exact modules listed in `allow_compile_modules`.
The built-in Familiar configuration allows the `Cantrip.Hot.*` modules it
declares for evolution; arbitrary namespace allowlists are no longer accepted.
The entity can hot-load those allowed modules into its current evaluator
session. It cannot redefine `Cantrip.Familiar`, the gate runtime, or any other
framework module — the parent rejects framework module names before compiling.

This is the entity's evolutionary surface. Combined with the BEAM's
hot-code-loading semantics (old version stays loaded for active processes;
new version takes over for new calls), the Familiar can try a scoped change.
When running under a port sandbox, port-session restart on timeout/crash also
discards the child runtime session.

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

- `sandbox: :port` plus `port_runner: [...]` for hosted or multi-tenant
  deployments that need a child process boundary.
- `sandbox: :dune` if the BEAM is shared with untrusted tenants and the
  prompt/capability text is written for Dune's narrower surface.
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
