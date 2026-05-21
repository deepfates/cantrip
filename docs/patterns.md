# Pattern Progression

This note describes the Elixir pattern progression implemented by
`Cantrip.Examples`. It is a bridge between `SPEC.md`, the example runner,
and production runtime choices.

Run examples with:

```bash
mix cantrip.example list
mix cantrip.example 04 --fake
```

## Example Map

| Example | Pattern focus | Spec terms | Production hook |
| --- | --- | --- | --- |
| 01 | LLM query | `LLM-*` | Provider adapter contract |
| 02 | Gate execution | `GATE`, `done` | Unit-test gates directly |
| 03 | Circle invariants | `CIRCLE-1`, `CIRCLE-2` | Reject bad config before runtime |
| 04 | Cantrip value | `CANTRIP-*` | Reusable script, fresh entity per cast |
| 05 | Ward composition | `WARD-*` | Most restrictive limits win |
| 06 | Medium choice | `MEDIUM-*` | One circle, one thinking substrate |
| 07 | Full agent | `CIRCLE-5`, `LOOP-7` | Filesystem gates and error steering |
| 08 | Folding | `LOOM-5`, `LOOM-6` | Prompt compression without loom loss |
| 09 | Composition | `COMP-*` | Child entities and batch fanout |
| 10 | Loom | `LOOM-*` | Audit trail and training substrate |
| 11 | Persistent entity | `ENTITY-*` | `summon` / `send` across episodes |
| 12 | Familiar | Appendix A.12 | Long-lived code-medium coordinator |
| 15 | Research fanout | RLM/council substrate | Parallel child readers plus synthesis |
| 16 | Persistent Familiar | RLM/council substrate | Durable loom plus filesystem children |

Examples 13 and 14 are covered by ACP/runtime and recursive-delegation
tests rather than treated as the main user-facing progression.

## Mediums

The active Elixir mediums are:

- `:conversation` - tool-calling chat. Best for interpretation,
  judgment, synthesis, naming, and direct answers.
- `:code` - Elixir as the entity's working medium. Best for branching,
  variables, loops, child cantrip construction, and aggregation.
- `:bash` - shell commands in a subprocess. Best for build/test/git/file
  operations where command invocation is the natural surface.

Browser/QuickJS/Taiko ideas from the old TypeScript implementation are
not active mediums. They are preserved as future backlog in
`docs/legacy-implementation-harvest.md`.

## Progression Narrative

### 1. Primitives

The early examples separate the LLM contract, gate execution, cantrip
construction, and ward enforcement. The key production rule is that a
bad circle should fail during construction, before any provider call.

### 2. Medium Physics

Conversation presents gates as tool definitions. Code presents gates as
Elixir functions in scope and persists bindings across turns. Bash
presents a command line and uses `SUBMIT:` for the final answer.

The medium determines the shape of thought. Use conversation for
semantic reads and code for composition. Avoid forcing a synthesis task
through code just because the parent is in code.

### 3. Delegation

Parents can call child entities with `call_entity`, `call_entity_batch`,
or with the public package API from code medium:

```elixir
{:ok, child} =
  Cantrip.new(%{
    identity: %{system_prompt: "Read what you are given and summarize it."},
    circle: %{type: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}
  })

{:ok, summary, child, _loom, _meta} = Cantrip.cast(child, content)
```

Use `Cantrip.cast_batch/1` for independent subtasks. The runtime keeps
request order in the returned results and grafts child turns into the
parent loom.

### 4. Loom And Folding

The loom is durable reality: turns, observations, events, parent-child
lineage, usage metadata, termination, and truncation. Folding is a view
over prompt context. It must never delete the underlying loom record.

### 5. Familiar

The Familiar is the production RLM-facing pattern. It is a persistent
Elixir code-medium entity that:

- observes a workspace through scoped gates
- reasons with variables and `loom.turns`
- creates child cantrips with `Cantrip.new/1`
- runs children with `Cantrip.cast/2` or `Cantrip.cast_batch/1`
- stores its loom durably
- can run as a REPL, single-shot CLI, or ACP server

This is the substrate for future council/review-round work: parallel
children already exist, but roles, structured verdicts, adjudication,
dissent, and durable decision events are still explicit backlog.

## Operational Checklist

1. Build circles with explicit `type`, `gates`, and `wards`.
2. Keep provider choice in configuration, not in task code.
3. Select the medium that matches the task's grain.
4. Use child entities for independent or differently-shaped work.
5. Keep large context in files, variables, or loom/artifact references;
   do not paste it through the parent prompt.
6. Stream events into the loom and protocol surfaces for auditability.
7. Use deployment isolation for unrestricted Elixir code medium; use
   Dune only when the tradeoff is intentional.
8. Treat the legacy TS/Python/Clojure implementations as git-history
   archives; active lessons live in the repository's
   `docs/legacy-implementation-harvest.md`.
