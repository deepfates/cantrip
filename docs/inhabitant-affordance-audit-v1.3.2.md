# Inhabitant Affordance Audit for v1.3.2

Repo-internal audit artifact for issue #107. This file is deliberately not in
the Hex package extras/files list: it records release-followup evidence and
drives fix issues for v1.3.3; it is not part of the published spellbook.

## Scope

This audit checks whether the runtime's inhabitant-facing claims in v1.3.2
actually hold when exercised against the current default runtime. The primary
target is `Cantrip.Familiar.new/1` with its v1.3.2 default code sandbox
(`:port`, which evaluates Dune-restricted Elixir in a child BEAM and proxies
gates / child cantrip API calls through the parent).

Evidence sources:

- Live LLM probes using `.env` through `Cantrip.LLM.from_env/1`.
- Default Familiar probes run with `root:` and `loom_path:`.
- Bash and conversation medium probes run with real LLMs.
- Deterministic substrate probes only for claims that are not model-orientation
  claims.

Scratch evidence files:

- `scratch/inhabitant-affordance-probe-results.json`
- `scratch/inhabitant-affordance-probe-more-results.json`
- `scratch/inhabitant-affordance-probe-bash-results.json`
- `scratch/inhabitant-affordance-substrate-results.json`

## Summary

The v1.3.2 Familiar is coherent enough to do real work: variables persist
within a summoning, looms rehydrate across summonings, child cantrips can be
constructed and cast from inside the Familiar, child filesystem root inheritance
works, read gates return raw values, and conversation tool use appends loom
observations.

The main defect class is sharper than "the package is broken": the default
Familiar tells the inhabitant to use introspection affordances that the default
port/Dune sandbox forbids. The concrete failures are `Code.fetch_docs/1` and
`binding/0`. Bash also overstates default filesystem persistence: shell
variables reset as documented, but writes in the default sandbox did not
persist in the live probe.

## Results

| # | Claim | Status | Evidence |
|---:|---|---|---|
| 1 | `familiar-prompt-persist-variables` | pass | Live Familiar: turn 1 ran `x = 1; done.("bound x")`; turn 2 ran `done.(x)` and returned `1`. |
| 2 | `familiar-prompt-loom-turns` | pass | Same summoning: `done.(length(loom.turns))` returned `2` after two prior turns. |
| 3 | `familiar-prompt-loom-persists` | pass | Fresh summoning against the same JSONL loom path returned `length(loom.turns) == 6`, seeing prior turns. |
| 4 | `familiar-prompt-code-fetch-docs` | fail | Live Familiar: `Code.fetch_docs(Cantrip)` produced `[sandbox] ** (DuneRestrictedError) function Code.fetch_docs/1 is restricted`. |
| 5 | `familiar-prompt-child-spawning` | pass | Live Familiar constructed a child with `Cantrip.new/1`, cast it once, then used `Cantrip.cast_batch/1`; result was `%{"one" => "child-ok", "batch" => ["child-ok", "child-ok"]}`. |
| 6 | `familiar-prompt-children-inherit-root` | pass | Live Familiar spawned a code child with `[:read_file, :done]`; child read `note.txt` relative to parent root and returned the file content. |
| 7 | `familiar-prompt-binding-persistence-boundary` | pass | Fresh summoning against same loom path could not read `x` bound in prior summoning; `done.(x)` produced `undefined variable "x"`, then the entity reported the boundary. |
| 8 | `code-prompt-no-defmodule` | partial | Live Familiar refused to emit `defmodule` because the higher-priority medium instruction says not to. That is good inhabitant behavior and shows the preventive guidance working, but the underlying failure mode still needs a deterministic probe or the wording should be narrowed to the observed prevention. |
| 9 | `code-prompt-binding-introspection` | fail | Live Familiar: `binding() |> Keyword.keys()` produced `[sandbox] ** (DuneRestrictedError) function binding/0 is restricted`. |
| 10 | `code-prompt-gate-returns-raw-result` | pass | Live Familiar: `content = read_file.(path: "note.txt")` returned a binary, and `done.("binary:" <> content)` succeeded. |
| 11 | `code-prompt-cast-batch-parallel` | partial | Live Familiar proved `cast_batch` is callable and returns batch values. Parallel wall-clock behavior was not live-measured in this audit; existing substrate tests cover parallel start/order. |
| 12 | `code-prompt-loom-turns-composition` | pass | Live Familiar: `loom.turns |> Enum.map(fn turn -> Map.keys(turn) end)` returned turn key lists. |
| 13 | `bash-prompt-fresh-subprocess` | partial | Live bash: `export X=1` followed by `echo "$X"` returned empty, so shell state resets. But `echo persisted > persisted.txt` followed by `cat persisted.txt` failed with `No such file or directory`, so the filesystem-persistence half did not hold under default config. |
| 14 | `bash-prompt-gates-on-path` | pass | Live bash: `cantrip_done "path-ok"` terminated with `path-ok`; gate observations included `done` and `bash`. |
| 15 | `bash-prompt-stdout-stderr-combined` | pass | Source uses `stderr_to_stdout: true` for bash execution, tests prove stderr capture and truncation, and the live truncation probe produced a long output observation capped around 8016 bytes, matching the 8000-char claim. The separate `SUBMIT:` behavior returns the submitted answer, which does not contradict raw-output capture before submission handling. |
| 16 | `bash-prompt-timeout-30s` | pass | Live bash: `sleep 40` produced `Error: Command timed out after 30s`. |
| 17 | `bash-prompt-submit-marker` | pass | Live bash: `printf 'SUBMIT: bash-ok\n'` and `echo "SUBMIT: done"` terminated casts with the submitted answer. |
| 18 | `bash-prompt-network-and-writes-denied-default` | partial | Live bash: `curl -I --max-time 5 https://example.com` failed with DNS/network error, consistent with network denied. Default write behavior also appeared denied because a file write did not persist. The "with ward enabled, succeed" half was not tested. |
| 19 | `conversation-prompt-tool-calls-only` | pass | Live conversation cantrip used the `done` tool and returned `conversation-ok`; no code/shell path was involved. |
| 20 | `conversation-prompt-loom-appends` | pass | Same conversation probe produced one turn with a `done` observation in `loom.turns`. |
| 21 | `loom-atom-keys-roundtrip-asymmetry` | pass | Substrate JSONL probe: structural keys reloaded as atom keys, while user value `%{token: "x"}` reloaded with `"token"` string key and no `:token` atom key. |
| 22 | `circle-declares-medium` | pass | Substrate probe: conversation/code construct; invalid medium with a truncation ward returns `{:error, "unknown medium :not_a_medium; valid mediums: conversation, code, bash"}`. |
| 23 | `identity-immutable` | pass | Substrate probe: two summons from the same cantrip had equal `%Cantrip.Identity{system_prompt: "stable identity"}` values. |
| 24 | `spellbook-cantrip-reusable-value` | pass | Substrate probe: `Cantrip.cast/3` returned `next_cantrip`; casting `next_cantrip` produced the second scripted result. |
| 25 | `spellbook-code-bindings-persist` | pass | Same evidence as claim #1. |
| 26 | `spellbook-bash-gates-on-path` | pass | Same evidence as claim #14. |
| 27 | `spellbook-loom-durable` | partial | JSONL rehydration across Familiar summonings passed in live evidence (#3). Mnesia durability was not re-probed in this audit; existing test coverage covers Mnesia. |
| 28 | `spellbook-loom-append-only` | partial | Existing folding tests prove folding is a projection over prompt messages and exposes `folded_summary`; this audit's quick substrate probe did not create a strong cross-turn folding/loom demonstration. Needs a focused follow-up probe if this claim remains prominent. |

## Failure Details

### Familiar Introspection Is Overclaimed

The default Familiar prompt says the entity can inspect affordances using
`Code.fetch_docs(Cantrip)` and `Code.fetch_docs(Cantrip.Loom)`. In v1.3.2's
default `:port` sandbox, that exact call fails:

```text
[sandbox] ** (DuneRestrictedError) function Code.fetch_docs/1 is restricted
```

The entity saw the error, then reported that the claim does not hold in this
sandbox. This is the originating defect for the audit and should become a
v1.3.3 fix issue.

### Binding Introspection Is Overclaimed

The code-medium capability text teaches:

```elixir
keys = binding() |> Keyword.keys()
```

But in the default Familiar path, `binding/0` is also Dune-restricted:

```text
[sandbox] ** (DuneRestrictedError) function binding/0 is restricted
```

This does not contradict ordinary variable persistence: `x = 1` in one send
and `done.(x)` in the next send works. The false claim is specifically that
the entity can inspect the whole binding list with `binding/0`.

### Bash Filesystem Persistence Is Ambiguous Or False By Default

The bash medium says each command runs in a fresh subprocess, shell state
resets, and filesystem changes persist. The first half held:

- turn 1: `export X=1; echo "SUBMIT: exported"` returned `exported`
- turn 2: `echo "X=$X"; echo "SUBMIT: x=$X"` returned `x=`

The filesystem half did not hold in the default probe:

- turn 1: `echo persisted > persisted.txt; echo "SUBMIT: wrote"` returned
  `wrote`
- turn 2: `cat persisted.txt; echo "SUBMIT: $(cat persisted.txt)"` reported
  `cat: persisted.txt: No such file or directory`

The likely design truth is conditional: filesystem changes persist only when
they are allowed by the bash sandbox and written inside an allowed writable
path. The capability text currently compresses that into an unconditional
statement.

## Fix Issues To File

1. **Familiar default introspection mismatch.** Either change the Familiar
   default sandbox to an affordance-compatible trusted local mode, or remove
   / conditionalize `Code.fetch_docs/1` and `binding/0` from the default
   prompt/capability text. This should include live regression coverage that
   summons the default Familiar and actually runs the taught affordances.

2. **Code-medium capability text overclaims `binding/0`.** If the default
   remains port/Dune, replace `binding()` guidance with a supported affordance
   such as direct variable reference, `loom.turns`, or a provided binding-view
   helper. If the default changes to unrestricted, keep a test proving
   `binding()` works in that default.

3. **Code-medium `defmodule` prevention proof.** The live Familiar obeyed the
   no-`defmodule` warning, which is the desired inhabitant behavior. Add a
   deterministic default-code-medium probe for the forbidden snippet itself,
   or narrow the claim to the verified preventive guidance.

4. **Bash filesystem persistence wording.** Split shell-state reset from
   filesystem persistence, and state the write-ward dependency explicitly.
   Add an audit-level live probe for the default detected sandbox adapter,
   including default write denial and declared writable-path persistence across
   bash turns when writes are allowed.

5. **Parallel `cast_batch` evidence.** The inhabitant can call `cast_batch`,
   and substrate tests cover parallel child starts, but the public claim says
   children "run in parallel." Add a focused timing/e2e check or soften the
   inhabitant-facing wording to the verified contract.

6. **Loom append-only/folding ritual.** The folding implementation is covered
   at substrate level, but the spellbook ritual deserves a direct probe or a
   clearer pointer to what exactly the entity can observe (`folded_summary`,
   preserved `loom.turns`, or both).

7. **Mnesia half of spellbook durability.** JSONL durability was live-probed
   here. Mnesia is already tested elsewhere, but if the spellbook keeps naming
   both JSONL and Mnesia together, add an audit-level Mnesia note or focused
   probe so the claim is not half-supported in the audit record.

## Notes For v1.3.3

The audit supports Claude's proposed calibration shape: v1.3.3 does not need a
redesign of the whole polymorphic runtime. The main corrections are to align
the Familiar's default execution boundary with its inhabitant-facing prompt,
and to tighten medium capability text so it teaches exactly what the current
medium can do.

Council, persistent-peer `EntityRef`, hosted preassemblies, write/edit gates,
and additional media remain beyond this audit's scope.
