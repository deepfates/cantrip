# dee-intr report

## Summary

Implemented interrupt, steer, queued sends, hard stop, and ACP cancel wiring for persistent Familiar entities.

- `Cantrip.interrupt/2` requests cancellation of the active episode at the next turn boundary and records loom events.
- `Cantrip.steer/2` injects a user message at the next boundary without ending the episode; it records control events and an intent.
- `Cantrip.send/3` now queues mid-turn sends and replies to each caller when its queued episode completes.
- `Cantrip.hard_stop/2` replies to active/queued callers, records `:hard_stopped`, kills the runner, and flushes/closes the loom.
- ACP `session/cancel` now calls runtime cancellation; Familiar maps interrupted prompts to `PromptResponse.stop_reason == :cancelled`.
- ACP prompt preparation stores a first-prompt entity pid before the blocking prompt call so first-turn cancel can reach the entity while preserving prompt trace ids.

## Reproduce commands

```bash
git checkout feat/interrupt-steer
mix test test/interrupt_steer_test.exs test/summon_test.exs test/acp_agent_test.exs
mix test test/familiar_behavior_test.exs
mix test
```

Evidence from this workspace:

```text
mix test test/interrupt_steer_test.exs test/summon_test.exs test/acp_agent_test.exs
28 tests, 0 failures

mix test test/familiar_behavior_test.exs
21 tests, 0 failures

mix test
3 properties, 664 tests, 0 failures
```

Note: in this managed sandbox, `mix test` needed escalation because Mix PubSub attempted a local TCP socket and the sandbox returned `:eperm`.

## Uncertainty

Interrupt is a safe-boundary cancel. It does not abort an in-flight provider call mid-request; the request is observed at the next runtime boundary, then the loom records the interruption and the active episode returns cancelled/interrupted.

## Filed tickets

None.
