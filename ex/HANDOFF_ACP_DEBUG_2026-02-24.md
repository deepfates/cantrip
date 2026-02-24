# ACP / CLI Debug Handoff (2026-02-24)

## Scope
This handoff records the verified ACP debugging outcomes in `cantrip-ex`, plus the parallel CLI/DX improvements, with exact commits for clean resume.

## Primary User-Visible Failures Observed
1. ACP request returned:
   - `{"code": -32602, "message": "prompt must contain a text content block"}`
2. ACP request returned:
   - `{"code": -32002, "message": "empty agent response"}`
3. UI sometimes showed `stopReason: end_turn` with no visible assistant text.
4. Separate auth failure observed once:
   - 401 invalid API key (one pasted key had a trailing `.`).

## Ground Truth (Verified)
1. Prompt-shape mismatch was real and is fixed.
   - ACP now accepts direct content-block arrays at `params.prompt`.
   - File: `lib/cantrip/acp/protocol.ex`
2. ACP final result payload now includes multiple text fields.
   - `result.content`, `result.text`, `result.output_text`.
   - File: `lib/cantrip/acp/protocol.ex`
3. `empty agent response` is intentionally emitted when cast normalizes to empty.
   - File: `lib/cantrip/acp/runtime/cantrip.ex`
4. Code-medium execution depends on `response.code`.
   - `EntityServer` code path only evaluates when `is_binary(code)`.
   - File: `lib/cantrip/entity_server.ex`
5. OpenAI-compatible adapter now derives `code` from assistant `content`.
   - File: `lib/cantrip/crystals/openai_compatible.ex`

## Critical Correction to Earlier Diagnosis
Earlier diagnosis was incomplete: ACP runtime had a code-style system prompt while circle behavior was not explicitly code-mode.

Fix applied:
- ACP runtime now sets `circle.type: :code`.
- File: `lib/cantrip/acp/runtime/cantrip.ex`

This aligns runtime semantics with the strict `done.(...)` contract.

## Committed Changes

### Commit A (ACP)
- SHA: `62fee31`
- Message: `Fix ACP prompt/result contract and code-mode execution`
- Includes:
  1. ACP prompt list parsing acceptance.
  2. ACP terminal result compatibility fields (`content`, `text`, `output_text`).
  3. ACP runtime explicit `:code` circle + empty-output guard.
  4. OpenAI-compatible `content -> code` normalization.
  5. ACP/adapter fixture + tests.

### Commit B (CLI / DX)
- SHA: `709ff79`
- Message: `Improve CLI ergonomics and add strict code-mode REPL`
- Includes:
  1. Shared CLI arg parser (`lib/cantrip/cli_args.ex`).
  2. REPL runtime + mix task (`lib/cantrip/repl.ex`, `lib/mix/tasks/cantrip.repl.ex`).
  3. CLI upgrades (`--help`, `--version`, `example --json`, `repl` modes).
  4. Mix task help/requirements improvements.
  5. README updates and CLI/REPL test coverage.

## Validation (Latest Runs)
1. ACP-focused suites passed:
   - `test/m8_openai_compatible_adapter_test.exs`
   - `test/m11_acp_protocol_test.exs`
   - `test/m15_acp_transcripts_test.exs`
   - `test/m16_acp_stdio_process_test.exs`
2. CLI/REPL suites passed:
   - `test/m13_cli_test.exs`
   - `test/m13_repl_defaults_test.exs`

## Repository State
- Working tree after these commits:
  - only this handoff document pending commit.
- Cleanup note:
  - root `cantrip` escript artifact was moved out of repo to `/tmp/cantrip-ex-escript.bin`.

## Resume Checklist (Next Session)
1. Compare pattern/DX behavior against older external repos (intended reference behavior).
2. Decide whether ACP strict code-mode should remain default or be profile-based.
3. Run full `mix verify` before merge (network/provider dependent tests may remain flaky).
4. Validate ACP output rendering end-to-end in Zed against the exact client fields consumed.

## One-Line Snapshot
The initial parser mismatch was real, empty responses were compounded by runtime mode misalignment, and the repo is now split into clean ACP and CLI/DX commits with targeted tests passing.
