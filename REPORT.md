# dee-perc Report

Branch: `codex/dee-perc-iex-legibility`

Code commit: `ad7b6f1 fix: teach loom transcript and bound turn inspection`

## Reproduction Commands

From the repository root:

```sh
mix test test/loom_api_test.exs test/loom_intent_persistence_test.exs test/familiar_test.exs test/code_medium_ergonomics_test.exs
```

Result: 71 tests, 0 failures.

```sh
mix test
```

Result: 3 properties, 653 tests, 0 failures.

## Evidence

- Familiar prompt no longer says memory is only prior turns. It teaches the real split: prompts in `loom.intents`, entity actions in `loom.turns`, and `Cantrip.Loom.transcript(loom)` as the chronological conversation view with a `you:`/`me:` example: `lib/cantrip/familiar.ex:43`.
- The prompt teaches bounded inspection helpers for raw code/bash turns whose `:code_state` carries a full binding snapshot: `lib/cantrip/familiar.ex:65`.
- The later Familiar environment paragraph repeats the same concrete affordance shape instead of the old bare `loom.turns` promise: `lib/cantrip/familiar.ex:211`.
- Code-medium capability text now teaches `loom.intents`, `loom.turns`, `Cantrip.Loom.transcript(loom)`, and the bounded projection helpers: `lib/cantrip/medium/code.ex:593`.
- `Cantrip.Loom.bounded_turn/2` is a pure view: it removes `:code_state` from the returned map and adds `:code_state_summary`; `bounded_turns/2` and `bounded_transcript/2` apply that projection without mutating the durable loom: `lib/cantrip/loom.ex:310`.
- The bounded projection test asserts the raw durable turn still has `:code_state`, while `bounded_turn/2`, `bounded_turns/2`, and `bounded_transcript/2` do not embed `:code_state`: `test/loom_api_test.exs:173`.
- Prompt/capability tests pin the taught affordances so they do not regress back to only `loom.turns`: `test/familiar_test.exs:146`.
- Existing ground truth was verified and left intact: `append_intent/3` stores intents as `role: "intent"` with `utterance: %{content: text}` (`lib/cantrip/loom.ex:255`), and `transcript/1` iterates the event log in append order (`lib/cantrip/loom.ex:273`).
- The stale Mnesia ordering bug was not re-fixed. Current storage writes monotonic integer keys (`lib/cantrip/loom/storage/mnesia.ex:34`) and reads them sorted by numeric key (`lib/cantrip/loom/storage/mnesia.ex:130`).

## Discovered Tickets

None.

## Uncertainty

None.
