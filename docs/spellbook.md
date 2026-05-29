# The Spellbook

Cantrip is a small runtime for entities summoned from language. This page holds
the vocabulary as a learnable system. You can read it as an operator deciding
whether to use Cantrip, or as a Familiar trying to understand the place you have
been summoned into. The words mean the same thing in both readings; the rituals
at the end of each section work the same way for both readers.

## Cantrip

A cantrip is a reusable value. It binds an LLM, an identity, and a circle into a
summoning. Constructing a cantrip with `Cantrip.new/1` does not start anything;
it produces the configured shape that a summoning will instantiate. Casting a
cantrip with `Cantrip.cast/3` summons one entity into the bound circle, runs it
through its turns, and returns the result, an updated cantrip value, the loom of
what happened, and termination metadata. Summoning a cantrip with
`Cantrip.summon/1` produces a supervised process that stays alive across many
sends, accumulating loom and medium state.

*Verify it.* Construct a cantrip and inspect it. Cast it twice and observe that
the returned `next_cantrip` carries forward runtime configuration. Summon a
code-medium cantrip, `Cantrip.send/3` to it twice, and the second send can read
bindings left by the first.

## Identity

Identity is who the entity is: the system prompt and model-facing options. It
is immutable. The cantrip's identity is bound at construction; each summoning
inherits it. Identity does not change across a session. What changes is the
loom, the bindings, the conversation history. The entity remains itself.

*Verify it.* Read the identity off any cantrip value with `cantrip.identity`.
Cast twice and confirm the identity is the same value both times.

## Medium

A medium determines the shape of thought inside the circle. Three are built in.
Conversation is tool calls only: the LLM speaks, chooses tools, and the host
executes the named gates. It fits interpretation, judgment, naming, and voice.
Code is sandboxed Elixir evaluation, with persistent bindings across turns and
gates available as closures. The default runs in a port-isolated child BEAM;
wards can select Dune or trusted unrestricted host evaluation. It fits
composition: gathering, transforming, branching, and fanning out. Bash runs one
shell command per turn in an OS-sandboxed subprocess, with declared gates
projected onto `PATH`. It fits work whose natural surface is command invocation.

*Verify it.* In a code-medium turn, bind a variable; in the next turn, read it
back. In a conversation-medium turn, call `done` with an answer and observe that
the cast terminates. In a bash-medium test under `Mix.env() == :test`, set
`medium_opts: %{sandbox: :passthrough}`, run `echo hello`, and observe stdout in
the next turn's observation.

## Gates

Gates are the authority the entity can exercise. They are named (`done`,
`read_file`, `list_dir`, `search`, `mix`, `compile_and_load`, `echo`) and
parameterized. Calling a gate produces an observation that the entity reads as
data on its next turn. A failed gate returns `is_error: true` with a structured
message; the entity reads the failure and adapts. Errors are observations, not
exceptions.

*Verify it.* Declare a circle with `read_file` and call `read_file.(path: ".")`
on a directory path; observe the structured error in your next turn. Call
`done.(answer)` and observe that the final answer is returned to the caller and
recorded in the loom.

## Wards

Wards are runtime constraints. They bound turn count (`max_turns`), recursion
depth (`max_depth`), sandbox choice, Mix task allowlist, hot-load module
allowlist, child-spawn policy, and other operational limits. Wards compose when
a child cantrip is cast from a parent code-medium turn: numeric wards tighten
with `min` (a child can only narrow), boolean wards tighten with `or` (a child
can only require more), and passthrough ward data remains explicit policy for
the gate or medium that enforces it. The runtime enforces wards. They are the
shape of the body the entity inhabits, not policy the entity is asked to
respect.

*Verify it.* Cast a cantrip with `max_turns: 1` on a task that needs two turns
and observe truncation with `meta.terminated == false`. Declare
`child_medium_allowlist: [:conversation]` and try to construct a code-medium
child; observe the structured rejection.

## Circle

The circle holds it all together: medium, gates, wards, and medium options. It
is the bounded place where the summoning happens. Constructing a cantrip without
a medium, without a `done` gate, or without a truncation ward fails validation;
you cannot summon an entity into an unbounded place.

*Verify it.* Try `Cantrip.new/1` with `circle: %{type: :code, gates:
[:read_file]}`. Observe the validation error naming what is missing.

## Loom

The loom is the durable record of every turn the entity and its children have
taken. It is the entity's autobiography. With JSONL or Mnesia storage, the loom
persists across summonings: re-summon the cantrip against the same loom storage
and the prior turns are available as `loom.turns`. The loom is append-only:
folding shrinks what the model sees on the next call but never deletes a turn.
Forking with `Cantrip.Loom.fork/4` branches a new trajectory from any prior
turn, restoring sandbox bindings to the fork point.

*Verify it.* Cast against a cantrip with `loom_storage: {:jsonl,
"tmp/loom.jsonl"}`; the file contains one line per event. Summon the same
cantrip against the same loom path; the previous turns appear in `loom.turns` of
the next cast. For the production Familiar path, construct it with the same
workspace `root` twice; the root-derived Mnesia table is reused, and the second
summoning sees the first summoning's turns through `loom.turns`.

## Entity

An entity is what arises when a cantrip is cast or summoned: a process whose
behavior is the pattern across the turns of the loom. The entity is not the LLM.
The LLM is one substrate the runtime calls; the identity, circle, and trajectory
are the shape that makes the entity recognizable. Fork the loom and the entity
branches into two. The entity's persistence is the loom's persistence.

*Verify it.* Construct a cantrip, summon it, send an intent, and stop the
process with `Process.exit(pid, :normal)`. Re-summon against the same loom
storage; the new process sees prior turns through `loom.turns`. The entity is
the trajectory, not merely the OS process. Code-medium binding restoration
across separate summonings is medium-specific; forks restore bindings explicitly
via snapshot, as documented by `Cantrip.Loom.fork/4`.

## Familiar

The Familiar is the packaged code-medium coordinator. It is a cantrip
preassembled with workspace observation gates (`list_dir`, `read_file`,
`search`), code-medium reasoning, durable loom storage, and a system prompt that
teaches composition and medium selection. Use it when you want a codebase-facing
entity without assembling the circle by hand. The Familiar is the first native
inhabitant of the spellbook: the entity designed to read this vocabulary and use
it.

*Verify it.* Run `mix cantrip.familiar` in a project workspace. Ask the Familiar
a question about your codebase. Read the loom JSONL or Mnesia table for what it
did and how it composed.

The grammar is small and the words are exact. If a word above does not behave
the way this page says, that is a defect, not a metaphor.
