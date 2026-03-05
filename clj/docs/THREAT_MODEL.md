# Threat Model

## Scope

This model covers cantrip runtime behavior for:

- composition (`call-agent`, `call-agent-batch`)
- code medium execution
- minecraft medium host bindings
- filesystem read gate

## Primary Risks

1. Unbounded nested composition
- Risk: runaway child spawning, denial-of-service, unbounded cost.
- Mitigation: `max-depth`, `max-batch-size`, `max-child-calls-per-turn`.

2. Arbitrary code execution expansion
- Risk: loading external namespaces, invoking dangerous runtime functions, shell/process abuse.
- Mitigation:
  - `allow-require` defaults to blocked behavior
  - forbidden symbol checks
  - `max-forms` and `max-eval-ms` limits

3. Host capability overexposure
- Risk: medium receives broad dependency map and can access unsafe internals.
- Mitigation: runtime now passes whitelisted medium dependencies.

4. Filesystem traversal
- Risk: `read` gate escapes configured root via `..` or absolute paths.
- Mitigation: root-escape guard in `read` path resolution.

5. Implicit world bindings
- Risk: minecraft behavior auto-loads host namespace unexpectedly.
- Mitigation: explicit dependency injection only for minecraft bindings.

## Out of Scope (Current State)

- OS-level sandboxing (process isolation, seccomp, container boundaries)
- network egress controls
- hard memory quotas
- deterministic CPU accounting

## Operational Guidance

- Treat ward defaults as mandatory policy in deployed environments.
- Keep `allow-require` disabled unless there is a reviewed allowlist plan.
- Run conformance and unit tests on every change to runtime/medium code paths.
