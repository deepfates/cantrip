# Deploying the Familiar

The Familiar is a long-lived BEAM-native entity. It reasons in Elixir,
spawns other entities at runtime, persists its loom across summons,
and can hot-load new code into its own runtime. This document is about
running it safely in production.

## The runtime shape

The Familiar lives in the same BEAM as the cantrip framework, the
loom storage, the protocol adapter (ACP / REPL / CLI), and the LLM
client. There is no separate sandbox process — the entity is an
Elixir evaluator hosted inside the same VM as everything else.

This shape is the point: it's what makes the Familiar's BEAM-native
powers real (supervised lifecycle, hot reload, Mnesia loom, telemetry,
distributed nodes). It's also what makes the deployment posture
matter.

## Safety, in layers

Safety is not provided by any single layer. Four layers compose:

### 1. Gate root validation

Filesystem-touching gates (`read_file`, `list_dir`, `search`) accept a
`root` dependency at construction time. Paths the entity passes get
validated against that root before the gate runs. A path that escapes
the root surfaces as an error observation, not a successful read.

This is configured by passing `:root` to `Cantrip.Familiar.new/1`:

```elixir
Cantrip.Familiar.new(llm: llm, root: "/path/to/workspace")
```

The Familiar's `list_dir` and `search` gates inherit this root. When
the Familiar spawns child cantrips with `cantrip.()`, the SpawnFn
merges the parent's dependencies into the child's gates (CIRCLE-10),
so a child given `gates: ["read_file", "done"]` automatically gets
the same root.

### 2. PROD-8 credential redaction

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

### 3. Deployment-level isolation

The BEAM process itself runs somewhere. The framework's claim of
in-circle safety is conditional on that "somewhere" being scoped
appropriately for the deployment.

For production: containerize the BEAM (Docker, systemd-nspawn, OCI
runtime of choice). Mount only the directories the Familiar should
reach. Drop OS capabilities the process doesn't need.

For development: run from a directory you're willing for the entity
to see. The PROD-8 redaction means even an accidental `.env` read
doesn't leak secrets to the model; the deployment isolation means
even an accidental `File.read!("/etc/passwd")` is bounded.

These two layers compose: redaction handles credentials wherever they
land; deployment isolation handles file paths that shouldn't be
reachable at all.

### 4. Opt-in `:dune` sandbox

For hardened-shared-BEAM scenarios where deployment isolation is
insufficient (multi-tenant SaaS where every Familiar runs in the same
BEAM as untrusted user data, e.g.), `Cantrip.Familiar.new/1` accepts
`sandbox: :dune`. This routes the code medium through
`Cantrip.CodeMedium.DuneSandbox`, which restricts language-level
`File.*`, `System.*`, `Process.*`, `spawn`, and `Code.*` (loading)
calls.

Cost: Dune also restricts some in-medium operations (`binding/0`,
`try/1`, `Code.ensure_loaded?/1`). The Familiar's prompt teaches
`binding()` introspection and pattern matching with `try/rescue`
fallback as native; under `:dune`, those teachings work less well,
and the entity has to fall back to "just reference variables by name"
and "errors land as observations the next turn sees."

Use `:dune` deliberately. Default is unrestricted code medium.

## Loom backends

The loom is the durable record of every turn the Familiar and its
children have ever taken. Three backends:

| Backend | Strengths | Use case |
| --- | --- | --- |
| **Mnesia** (default for workspace-scoped Familiars) | BEAM-native, transactional, queryable, distributable across nodes | Production |
| **JSONL** | Portable, exportable, human-readable | Development, sharing traces, off-BEAM consumers |
| **DETS** | Crash-safe on-disk, faster than JSONL | Single-node deployments without Mnesia |
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

# DETS
Cantrip.Familiar.new(llm: llm, root: "/path/to/workspace",
                     loom_storage: {:dets, [file: "/var/cantrip/loom.dets"]})

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
| `allow_compile_namespaces` | `["Elixir.Cantrip.Hot."]` | Hot-reload restricted to a sub-namespace |

Tune per deployment. Long-running workflows may want higher
`max_turns`; cost-sensitive deployments may want lower
`code_eval_timeout_ms`. The Familiar's prompt does not need to know
these numbers — the wards are enforced by the circle, not by the
entity.

## Hot reload (self-modification)

`compile_and_load` is enabled in the Familiar's default gates, scoped
to the `Cantrip.Hot.*` namespace. The entity can write new Elixir
modules into that subtree and hot-load them into the running BEAM. It
cannot redefine `Cantrip.Familiar`, `Cantrip.Gate`, or any other
framework module — the ward enforces the namespace boundary.

This is the entity's evolutionary surface. Combined with the BEAM's
hot-code-loading semantics (old version stays loaded for active
processes; new version takes over for new calls) and supervisor
restart on crash, the Familiar can try a change and roll back if the
change breaks something.

Deployments that don't want hot reload at all: pass an empty
`allow_compile_namespaces` list, or strip `compile_and_load` from the
gate set by constructing your own circle via `Cantrip.new/1` instead
of `Cantrip.Familiar.new/1`.

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
- PROD-8 redaction is always on; nothing to configure.
- `:telemetry` event handlers wired to your observability stack
  (every gate call, every turn, every fold emits events).
- Mnesia's persistence directory mounted to durable storage.

Optional:

- `sandbox: :dune` if the BEAM is shared with untrusted tenants.
- Mnesia replication across cluster nodes if you're running
  distributed.

## What the framework does NOT provide

Honest list:

- **Network isolation.** Outbound HTTP from the entity (e.g., LLM API
  calls) goes wherever your DNS resolves. If you need egress
  filtering, that's a deployment-level firewall concern.
- **Resource accounting per tenant.** `max_turns` is a per-cast bound,
  not a per-tenant budget. Multi-tenant deployments need their own
  accounting layer.
- **Cross-restart entity state beyond the loom.** The Familiar's
  ephemeral in-process state (variable bindings outside the loom)
  does not survive a BEAM restart. The loom does. Long-running
  state belongs in the loom.

These are deliberate scope boundaries, not bugs.
