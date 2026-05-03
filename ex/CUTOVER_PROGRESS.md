# Elixir Runtime Cutover Progress

This is the local running log for autonomous cutover slices. User-facing chat
should stay light; detailed "done / next / doing" notes go here.

## Current Loop

- Done: moved request preparation, response classification, classified medium
  execution, provider calls, event envelopes, and usage accumulation out of the
  `EntityServer` hot path and into explicit runtime boundaries.
- Verified: latest full suite was `397 tests, 0 failures`.
- Done: verified `final_response` is single-emitted in the current tree and
  `m23_streaming_test` still pins exactly one final response.
- Done: added `Cantrip.Turn.turn_attrs/5`, cut `EntityServer` over, and full
  suite is green: `398 tests, 0 failures`. Formatting check passed for touched
  files.
- Done: extracted continuation message construction into
  `Cantrip.Turn.next_messages/3`, removed code feedback/tool-result string
  helpers from `EntityServer`, and focused tests are green.
- Verified: continuation-message slice full suite is green:
  `400 tests, 0 failures`; formatting check passed for touched files.
- Next: move the turn termination decision out of `EntityServer` and into
  `Cantrip.Turn`.
- Doing now: add red-green tests for desired termination invariants, cut
  `EntityServer` over, then run focused verification.
- Done: added `Cantrip.Turn.terminated?/3`, cut `EntityServer` over, and
  pinned the desired termination cases.
- Verified: `mix test test/runtime_boundary_spike_test.exs` is green:
  `26 tests, 0 failures`; formatter check passed.
- Next: run broader focused runtime tests, then full suite. If green, extract
  protocol-facing tool event construction out of `EntityServer`.
- Doing now: broader focused verification.
- Verified: broader focused runtime tests are green: `24 tests, 0 failures`.
- Verified: full suite after termination slice is green: `401 tests, 0 failures`.
- Next: extract protocol-facing tool event construction out of `EntityServer`.
- Doing now: move paired `tool_call`/`tool_result` event construction into
  `Cantrip.Event`, pin the shape, and rerun focused verification.
- Done: moved paired `tool_call`/`tool_result` construction into
  `Cantrip.Event.tool_events/1`; `EntityServer` now only emits the events.
- Verified: targeted event/stream/renderer tests are green:
  `46 tests, 0 failures`; formatter check passed.
- Next: full suite for the tool-event slice. If green, extract empty-turn
  detection into the turn/event boundary.
- Doing now: full suite.
- Verified: full suite after tool-event slice is green:
  `402 tests, 0 failures`.
- Next: extract empty-turn detection into the turn/event boundary.
- Doing now: add `Cantrip.Turn.empty_turn_events/3`, cut `EntityServer` over,
  then run focused event/runtime tests.
- Done: added `Cantrip.Turn.empty_turn_events/3` and removed empty-turn
  branching from `EntityServer`.
- Verified: focused event/runtime tests are green: `40 tests, 0 failures`;
  formatter check passed.
- Next: full suite after the empty-turn slice. If green, look at final response
  value/meta construction as the next extractable turn boundary.
- Doing now: full suite.
- Verified: full suite after empty-turn slice is green:
  `403 tests, 0 failures`.
- Next: extract final response value/meta construction from `EntityServer`.
- Doing now: add `Cantrip.Turn.final_response/4`, cut `EntityServer` over,
  then run focused streaming/runtime tests.
- Done: added `Cantrip.Turn.final_response/4` for final value/meta and fatal
  code-medium error handling; `EntityServer` now emits/returns the result.
- Verified: focused streaming/runtime tests are green:
  `44 tests, 0 failures`; formatter check passed.
- Next: full suite after the final-response slice. If green, inspect remaining
  `execute_turn/4` responsibilities and choose the next small cut.
- Doing now: full suite.
- Verified: full suite after final-response slice is green:
  `404 tests, 0 failures`.
- Next: move child-subtree grafting into `Cantrip.Loom`.
- Doing now: add `Cantrip.Loom.append_child_subtrees/2`, remove the duplicate
  private helper from `EntityServer`, and run focused composition tests.
- Done: added `Cantrip.Loom.append_child_subtrees/2`, pinned child/grandchild
  parent remapping, and removed the duplicate private helper from
  `EntityServer`.
- Verified: focused runtime/composition tests are green:
  `55 tests, 0 failures`; formatter check passed.
- Next: full suite after the loom-subtree slice. If green, move parent
  continuation-turn construction into the loom projection boundary.
- Doing now: full suite.
- Verified: full suite after the loom-subtree slice is green:
  `405 tests, 0 failures`.
- Next: move parent continuation-turn construction into the loom projection
  boundary.
- Doing now: add `Cantrip.Loom.append_parent_continuation/5`, cut
  `EntityServer` over, and run focused loom/composition tests.
- Done: added `Cantrip.Loom.append_parent_continuation/5` and removed the
  continuation-turn construction block from `EntityServer`.
- Verified: focused loom/composition tests are green:
  `56 tests, 0 failures`; formatter check passed.
- Next: full suite after the continuation-turn slice. If green, inspect
  `execute_turn/4` again and choose the next small cut.
- Doing now: full suite.
- Verified: full suite after the continuation-turn slice is green:
  `406 tests, 0 failures`.
- North star: the current shape is materially closer to the solid version:
  `EntityServer` is now mostly lifecycle/recursion/emission, while turn
  decisions, event construction, finalization, and loom projection have named
  boundaries.
- Next: collapse the remaining turn-to-loom append sequence into one explicit
  projection helper, likely `Cantrip.Loom.append_executed_turn/5` or
  `Cantrip.Turn.append_to_loom/5`, so `EntityServer` stops coordinating
  parent id, child subtree presence, and continuation sequence itself.
- Doing next: choose the cleaner boundary by reading the immediate call sites,
  then red-green the intended projection shape before cutting over.
- Done: chose the loom boundary and added `Cantrip.Loom.append_executed_turn/4`
  to append the parent turn, graft child subtrees, and add parent continuation
  as one durable loom operation.
- Verified: focused loom/composition tests are green:
  `57 tests, 0 failures`; formatter check passed.
- Doing now: full suite after the executed-turn loom slice.
- Verified: full suite after the executed-turn loom slice is green:
  `407 tests, 0 failures`.
- Closed this heartbeat: the remaining parent-turn/child-subtree/continuation
  coordination moved behind `Cantrip.Loom.append_executed_turn/4`, keeping
  Solid V1 centered on durable loom reality and mechanically ordered runtime
  behavior.
- Next: inspect what remains in `EntityServer.execute_turn/4` for Solid V1
  only. Likely candidates are small: step-complete/final-response emission
  ordering checks, diagnostics safety checks, and PR-readiness cleanup. Avoid
  V1.5/V2 projection/artifact/evolution work unless explicitly requested.
- Next slice: make runtime event ordering explicit without moving into V1.5
  projections.
- Doing now: add `Cantrip.Event.turn_runtime_events/3`, cut `EntityServer`
  over, and verify that thought/code events, tool call/result pairs, and
  empty-turn warnings are emitted from one ordered list.
- Done: added `Cantrip.Event.turn_runtime_events/3`, moved empty-turn warning
  construction into the event boundary, and cut `EntityServer` over to emit one
  ordered runtime-event list per turn.
- Verified: focused runtime/stream/renderer tests are green:
  `56 tests, 0 failures`; formatter check passed.
- Doing now: full suite after the runtime-event ordering slice.
- Verified: full suite after the runtime-event ordering slice is green:
  `407 tests, 0 failures`.
- Next slice: PR-readiness warning cleanup that stays inside Solid V1. The full
  suite is green but still emits a few local warnings; removing them improves
  reviewability without changing runtime design.
- Doing now: fix obvious test warnings, then run the affected tests and full
  suite.
- Done: removed the unused example loom binding, duplicate hot-reload circle
  type key, telemetry helper default warning, and telemetry local-function
  handler notices.
- Verified: affected tests are green: `55 tests, 0 failures`; telemetry-only
  run is green: `8 tests, 0 failures`; formatter check passed.
- Doing now: full suite after PR-readiness warning cleanup.
- Verified: full suite after PR-readiness warning cleanup is green:
  `407 tests, 0 failures`; the previous compiler/telemetry warnings are gone
  from this pass. Remaining nofile warning/error text comes from intentional
  conformance cases.
- Next slice: run Credo as a reviewability scan and only address high-signal
  Solid V1 issues. Avoid churny style/refactor sweeps unless they touch current
  runtime correctness or obvious PR comments.
- Doing now: `mix credo`.
- Done: addressed the high-signal Credo findings in the Solid V1 surface:
  underscored ACP error codes, removed the CLI unused-Enum-return warning,
  replaced obvious `length(list) > 0` checks, removed the conformance TODO tag,
  and cleaned the touched conformance runner formatting.
- Verified: targeted ACP/conformance/streaming/CLI tests are green:
  `51 tests, 0 failures`; targeted ACP/conformance retest is green:
  `32 tests, 0 failures`; formatter check passed for touched files.
- Verified: `mix credo` now reports no warnings or software-design findings.
  Remaining findings are style/refactor opportunities, mostly old example
  `with` shape and conformance helper `map_join` suggestions.
- North star: this slice is deliberately boring. A reviewable Solid V1 needs
  the runtime spine to be clear and the test signal to be trustworthy; it does
  not need us to polish every old example before the cutover lands.
- Doing now: full suite after Credo warning cleanup.
- Verified: full suite after Credo warning cleanup is green:
  `407 tests, 0 failures`.
- Closed this loop: warning cleanup is done enough for Solid V1. Remaining
  Credo output is non-blocking style/refactor work.
- Next slice: safe diagnostics and ACP lifetime checks. This stays in Solid V1
  because diagnostics and streaming are part of the operational runtime surface;
  the goal is to ensure diagnostic helpers cannot leak secrets or orphan bridge
  processes while ACP final responses remain single-sent.
- Doing now: inspect diagnostics/EventBridge/ACP tests and close any remaining
  concrete safety gaps with red-green coverage.
- Done: added coverage that printed diagnostics are redacted by default and
  that custom/test EventBridge processes default to monitoring their caller
  when there is no pid-backed ACP connection. Also captured diagnostics test
  output so the suite stays quieter.
- Verified: diagnostics/EventBridge tests are green:
  `37 tests, 0 failures`; formatter check passed.
- Next: run broader ACP-focused tests, including handler streaming, to confirm
  the lifetime/diagnostic checks did not disturb single-final-response behavior.
- Doing now: ACP-focused verification.
- Verified: broader ACP-focused verification is green:
  `55 tests, 0 failures`.
- Next: full suite after the safe diagnostics/bridge lifetime slice.
- Doing now: full suite.
- Verified: full suite after the safe diagnostics/bridge lifetime slice is
  green: `409 tests, 0 failures`.
- Found: repo-wide `mix format --check-formatted` still fails on older/touched
  files outside the immediate slice. For a cutover PR, a clean formatter signal
  is better than leaving a known mechanical failure.
- Doing now: run repo-wide `mix format`, then rerun full verification.
- Done: ran repo-wide `mix format`.
- Verified: `mix format --check-formatted` passes.
- Verified: full suite after repo-wide format is green:
  `409 tests, 0 failures`.
- Verified: `mix credo` still has no warnings or software-design findings; the
  remaining output is non-blocking readability/refactor advice.
- Next: final local hygiene pass for reviewability: diff whitespace check,
  compile warnings as errors, and then inspect the changed-file map for any
  accidental V1.5/V2 drift before choosing the next Solid V1 slice.
- Doing now: local hygiene verification.
- Verified: `git diff --check` passes.
- Verified: `mix compile --warnings-as-errors` passes.
- Found and corrected: `Cantrip.Loom.Events` was a small V1.5 evolution
  vocabulary in runtime code. The idea belongs in the plan, but not in Solid V1
  implementation. Removed that module and changed loom tests to pin only the
  generic append/read event-log behavior.
- Verified: focused loom tests are green: `10 tests, 0 failures`.
- North star: this re-centers the branch on durable loom reality without
  prematurely committing to artifact/evaluation/promotion APIs.
- Doing now: full suite and formatter after removing the V1.5 runtime surface.
- Verified: formatter still passes after removing the V1.5 runtime surface.
- Verified: full suite is green after that scope correction:
  `409 tests, 0 failures`.
- Verified: `mix credo` still has no warnings or software-design findings.
- Current shape: `EntityServer` is down to 647 lines, `Circle` is down to 107
  lines, and the extracted runtime spine is now visible in `Turn`, `Event`,
  `Loom`, `Medium`, `Gate.Executor`, `ProviderCall`, and `WardPolicy`.
- Next: write a concise PR draft that explains the Solid V1 spine, verification
  status, and deliberately deferred V1.5/V2 work. This is the handoff artifact
  for reviewability, not a new runtime feature.
- Doing now: PR draft.
- Done: added `CUTOVER_PR_DRAFT.md` with a Solid V1 summary, runtime/protocol
  fix list, verification status, and explicit deferred V1.5/V2 scope.
- Verified: formatter check passes for progress/spike/PR draft docs, and
  `git diff --check` still passes.
- Next: the branch is locally coherent enough for a review pass. Remaining work
  is either PR mechanics (commit/push/open PR) or a final source-level review
  of the changed runtime modules for subtle behavioral risks.
- Continuing autonomously: started source-level review of the runtime spine.
- Reviewed and corrected course: a suspected continuation-sequence bug was
  actually a scope invariant. Turn `sequence` remains local to the entity/subtree
  being projected into the loom: parent turns can be sequence 1/2 while a grafted
  child turn keeps its own sequence 1. The boundary test now states this instead
  of forcing global turn sequences.
- Doing now: focused conformance/runtime verification after restating that
  invariant.
- Verified: focused conformance/runtime/composition tests are green:
  `62 tests, 0 failures`; formatter check passed.
- Next: full suite after the sequence-scope review.
- Doing now: full suite.
- Verified: full suite after the sequence-scope review is green:
  `409 tests, 0 failures`.
- Verified: `mix compile --warnings-as-errors` still passes.
- Next: continue source-level review on medium/gate/provider boundaries for
  Solid V1 behavioral traps.
- Doing now: inspect `Gate.Executor`, medium adapters, and `ProviderCall`.
- Found and fixed: provider retries were still allowed for streaming requests.
  Since streamed output may already have reached subscribers, retrying can replay
  unsafe partial output. `ProviderCall` now disables retry when the request has
  an event emitter, and the boundary test pins single-attempt behavior.
- Verified: focused provider/production/streaming tests are green:
  `41 tests, 0 failures`; formatter check passed.
- Doing now: full suite after streaming-retry guard.
- Verified: full suite after streaming-retry guard is green:
  `410 tests, 0 failures`.
- Verified: `mix compile --warnings-as-errors` passes.
- Next: rerun formatter/Credo/diff checks, then update PR draft with the
  streaming-retry safety fix and current test count.
- Doing now: final hygiene pass.
- Verified: `mix format --check-formatted` passes.
- Verified: `git diff --check` passes.
- Verified: `mix credo` still has no warnings or software-design findings;
  remaining output is non-blocking readability/refactor advice.
- Done: updated `CUTOVER_PR_DRAFT.md` with the streaming-retry guard and current
  `410 tests, 0 failures` status.
- Next: continue source-level review on remaining protocol/diagnostic edges or
  prepare PR mechanics when requested.
- Heartbeat north star: Solid V1 still means ordered event reality, supervised
  BEAM lifetimes, explicit medium/gate/ward boundaries, stable ACP/CLI, and no
  V1.5 evolution APIs.
- Found and fixed: ACP direct-answer fallback was still available for streaming
  sessions when the bridge returned `:no_answer`. That is useful for
  synchronous runtimes, but unsafe for streaming runtimes because bridge flush
  can race with final-response delivery. Runtime sessions that stream now mark
  `streaming?: true`, and AgentHandler only direct-sends `:no_answer` for
  non-streaming sessions.
- Verified: focused ACP/Familiar tests are green: `40 tests, 0 failures`;
  formatting was applied to touched files.
- Doing now: full suite after the streaming fallback guard.
- Verified: full suite after the ACP streaming fallback guard is green:
  `411 tests, 0 failures`.
- Found and fixed during hygiene: a few easy Credo readability issues were
  still in the branch (`with` forms that wanted `case`, a test-support
  moduledoc, and two tiny refactors around diagnostics/feedback formatting).
  This is not architectural work, but it makes the PR quieter for reviewers.
- Verified: focused examples/runtime/ACP diagnostics tests are green:
  `87 tests, 0 failures` across the focused runs.
- Verified: `mix compile --warnings-as-errors` passes after those readability
  edits.
- Verified: `mix credo` now reports no warnings, readability, or software-design
  findings; only non-blocking refactor suggestions remain.
- Done: updated `CUTOVER_PR_DRAFT.md` with the ACP streaming-session fallback
  guard and current `411 tests, 0 failures` status.
- Next: rerun final full-suite/formatter/diff hygiene after the tiny test
  warning cleanup, then decide whether the next loop should be PR mechanics or
  one more source-level pass over protocol comments/docs.
- Verified: final formatter check passes.
- Verified: final diff whitespace check passes.
- Verified: final compile hygiene passes with `--warnings-as-errors`.
- Verified: final full suite is green and warning-free in the touched test path:
  `411 tests, 0 failures`.
- Current PR size after the cutover is `65 files changed, 1926 insertions(+),
  2117 deletions(-)`, mostly because the old `Circle`/`EntityServer` control
  mass moved into named runtime boundary modules.
- Next: the Solid V1 slice is reviewable locally. The highest-value next action
  is PR mechanics (stage/commit/push/open a draft PR) unless another heartbeat
  asks for one more code-level sweep first.
- Heartbeat north star: keep Solid V1 grounded in one durable event reality and
  supervised runtime boundaries; do not let old "single sender" language
  overstate what the ACP bridge guarantees.
- Found and fixed: `EventBridge` moduledoc still claimed a pure single-sender
  ordering model. The implementation is safer and more precise now: streaming
  runtimes route final answers through the bridge, while AgentHandler direct
  fallback is only for non-streaming sessions or dead bridges. Updated the docs
  to match that actual invariant.
- Verified: formatter check passes after the doc correction.
- Verified: diff whitespace check passes.
- Verified: focused ACP bridge/streaming tests are green:
  `30 tests, 0 failures`.
- Next: PR mechanics remains the next concrete task; code-level Solid V1 risks
  found in this heartbeat were documentation drift, not behavior drift.
- Consolidation pass north star: the cutover should read as a BEAM-native
  entity runtime, not a bag of extracted helpers. The loom is durable reality;
  `EntityServer` is supervised identity/lifecycle; `Turn`, `Gate`, `Medium`,
  `WardPolicy`, `ProviderCall`, and `Event` are explicit runtime boundaries;
  versioned evolution remains later substrate work.
- Found and fixed: the new spine's module docs lagged behind the code.
  `EntityServer`, `Turn`, `Gate`, `Medium`, and `Loom` now explain their Solid
  V1 responsibilities directly, without "spike boundary" or old M2 wording.
- Verified: focused runtime/loom/LLM-view tests are green:
  `48 tests, 0 failures`.
- Verified: `mix compile --warnings-as-errors` passes after the consolidation
  doc pass.
- Verified: `mix credo` still has no warnings, readability, or software-design
  findings; only non-blocking refactor suggestions remain.
- Verified: formatter and diff whitespace checks pass.
- Next: this answered the "does the spine feel inevitable?" hesitation. I do
  not see a structural mismatch that should block freezing Solid V1; PR
  mechanics is again the concrete next step.
- PR follow-up north star: review feedback should harden Solid V1's event
  reality and medium boundaries without reopening V1.5 scope.
- Addressed PR review: ACP bridge flushing now has a real entity-sent barrier.
  ACP runtimes opt into `stream_barrier?: true`; `EntityServer` sends a
  same-sender `Cantrip.Event.barrier/2` before replying, including child
  entities, so the handler's later `flush/2` can no longer reset before late
  final-response events from the previous prompt.
- Addressed PR review: bash medium telemetry now emits
  `[:cantrip, :bash, :eval]` instead of sharing the code-medium
  `[:cantrip, :code, :eval]` event name.
- Verified: focused ACP/streaming/telemetry tests are green:
  `43 tests, 0 failures`.
- Verified: full suite is green after PR review fixes:
  `413 tests, 0 failures`.
- Verified: `mix compile --warnings-as-errors`, `mix format --check-formatted`,
  `git diff --check`, and `mix credo` all remain clean at the same standard as
  before: Credo reports only non-blocking refactor suggestions.
- Next: commit and push the PR-review fix commit, then reply/resolve the two
  Copilot review comments.
