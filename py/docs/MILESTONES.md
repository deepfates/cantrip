# Cantrip-Py Milestones

## M1: Canonical Depends Surface

Status: completed

User stories:
- As a cantrip author, I configure circle/gate resources through one canonical field (`depends`).
- As an entity author, I can override child resource bindings via `call_entity(..., depends=...)`.
- As a maintainer, legacy `dependencies` is rejected to prevent mixed dialects.

Acceptance:
- `Circle(..., depends=...)` works and `Circle(..., dependencies=...)` fails.
- Gate config uses `{"name": "...", "depends": {...}}`.
- `call_entity` accepts `depends` and rejects `dependencies`.
- Conformance CIRCLE-10 passes with `depends`.

## M2: ACP Contract Stability

Status: completed

User stories:
- As a Toad/Zed user, prompts always return non-empty ACP output when a cast has no final answer.
- As an ACP client, I receive valid `session/update` notifications and `session/prompt` result output.

Acceptance:
- `session/prompt` always emits text output.
- ACP tests cover null/empty cast outcomes with deterministic fallback text.

## M3: Medium Composition Hardening

Status: completed

User stories:
- As a cantrip author, I can compose code/browser medium behavior through circle and child `depends`.
- As a reviewer, I can verify depth/ward constraints still hold under medium overrides.

Acceptance:
- Mixed `call_entity_batch` medium scenarios stay green.
- Browser and code medium tests cover dependency overrides and error behavior.
- Depends precedence (`global -> circle -> call_entity override`) is covered by tests.

## M4: End-to-End Capstone Operability

Status: completed

User stories:
- As a user, I can use pipe, REPL, and ACP stdio modes against the same capstone runtime.
- As an operator, I can diagnose failures from deterministic logs and event outputs.

Acceptance:
- `scripts/capstone.py` supports pipe/REPL/ACP with canonical `depends` config.
- Docs reflect current CLI and runtime naming.
- Non-live full suite remains green.
- Executable tests cover pipe mode and ACP stdio prompt roundtrip.
