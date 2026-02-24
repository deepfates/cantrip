# Mission Checklist

This file defines the current completion criteria for Cantrip.

An iteration is "done" only when every applicable item below is green.

## 1) Conformance

1. `mix verify` passes in a clean working tree.
2. All non-skipped rules in [`tests.yaml`](/Users/deepfates/Hacking/github/deepfates/cantrip-ex/tests.yaml) have rule-mapped ExUnit coverage.
3. Any behavior change includes a failing test first (red), then minimal fix (green), then refactor.

## 2) Runtime Core

1. Loop alternation, termination, truncation, and done-ordering behavior stay compliant.
2. Composition invariants stay compliant (`call_agent`, `call_agent_batch`, depth constraints, parent-child linkage).
3. Production semantics stay compliant (retry single-turn accounting, cumulative usage, folding, ephemeral projection).

## 3) ACP Contract

1. ACP protocol tests cover supported prompt payload shapes from real clients.
2. ACP transcript fixture tests cover multi-step request sequences (initialize/session/new/session/prompt) and error paths.
3. ACP stdio process test validates JSON-RPC behavior in a separate BEAM process.
4. `session/new` and `session/prompt` behavior remains backward-compatible for accepted payload variants.
5. Any ACP bug report gets a regression test in `test/m11_acp_protocol_test.exs` or a fixture/module in the ACP suite.

## 4) Entity Progression

1. Progression examples (`01..16`) run green in scripted mode.
2. Entity progression fixture tests validate recursive delegation, cancellation/truncation propagation, and subtree invariants.
3. Cancellation/truncation propagation (`COMP-9`) remains validated under concurrent child delegation.
4. Loom subtree history remains append-only and auditable across parent/child paths.

## 5) Operations and Safety

1. Guarded hot reload remains ward-enforced (`allow_compile_modules`, optional path/hash controls).
2. Signer-based compile verification remains covered (`allow_compile_signers` + signature checks).
3. Storage adapters preserve append-only loom semantics.
4. Lightweight storage path remains available (`{:auto, %{dets_path: ...}}` with Mnesia->DETS fallback).
5. Real-crystal integration tests are exercised when provider env is configured.

## 6) Documentation Integrity

1. `README.md` status/test count is synced to current passing baseline.
2. `MASTER_PLAN.md` reflects implemented milestones and remaining follow-ups.
3. Any canonical semantic decision changes are recorded in `SPEC_DECISIONS.md`.
