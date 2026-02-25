# Changelog

All notable changes to this project are documented in this file.

## [0.1.0] - 2026-02-25

### Added
- Core runtime composition through `call-agent`/`call-agent-batch` host bindings in code medium.
- Loom subtree recording for nested composition with per-entity sequence tracking.
- Depth-aware child crystal derivation (`child_crystal_lN` resolution).
- Runtime composition wards:
  - `max-depth`
  - `max-batch-size`
  - `max-child-calls-per-turn`
- Code/minecraft medium sandbox wards:
  - `allow-require`
  - `max-eval-ms`
  - `max-forms`
- Filesystem read root-escape guard for `read` gate.
- Domain validation for new ward configs.

### Changed
- Conformance runner now exercises core runtime behavior directly.
- Removed composition simulation shim from conformance execution.
- Runtime now validates `call-agent` request shape and batch input shape.
- Minecraft medium uses explicit host injection only (no implicit namespace resolution).

### Security
- Blocked risky code symbols in medium execution path (`eval`, `load-string`, shell/process patterns).
- Added execution timeout and form-count limits to reduce abuse surface.

### Verification
- Unit tests: `83` tests, `180` assertions, `0` failures.
- Conformance batch: `supported=66`, `unsupported=0`, `pass=66`, `fail=0`.
