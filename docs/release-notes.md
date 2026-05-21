# Release Notes

## Current Iteration

### Added

1. ACP compatibility hardening
   - Flexible prompt parsing for client payload variants.
   - Fixture-driven payload and transcript regression suites.
   - Separate-process ACP stdio JSON-RPC integration test.

2. Entity progression verification
   - Fixture scenarios for recursive delegation, cancellation propagation, and subtree invariants.
   - Additional COMP-9 concurrent truncation stress test.

3. Hot-reload trust model upgrade
   - `compile_and_load` now supports signer-based verification via `allow_compile_signers`.
   - Signature acceptance/rejection tests added.

4. Lightweight durable loom storage path
   - Optional Mnesia adapter.
   - `{:auto, ...}` storage adapter that prefers Mnesia and falls back to DETS.

5. Mission/process documentation
   - Explicit completion checklist.
   - Signer-key runbook.
   - Loom storage strategy guide.

### Verification Baseline

`mix verify` passes with **101 tests, 0 failures**.
