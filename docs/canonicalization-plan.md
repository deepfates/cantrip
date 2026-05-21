# Elixir Canonicalization Plan

Cantrip is now an Elixir-first project. The old TypeScript, Python, and
Clojure implementations have been removed from the active tree after
their remaining lessons were harvested.

## Done In This Cut

- Root README now points to the Elixir runtime as canonical.
- Legacy implementation lessons and contract gaps are captured in
  `docs/legacy-implementation-harvest.md` and
  `docs/legacy-contract-backlog.md`.
- Repository conformance helper now runs the Elixir conformance suite
  instead of attempting to test removed implementations.
- Elixir package metadata has a real description, docs metadata, and Hex
  package fields.
- Legacy implementation directories are removed from the working tree.

## Package Posture

The Mix application, public module, CLI, and repository identity are
`Cantrip` / `:cantrip` / `cantrip`.

The ACP dependency decision is settled: Cantrip depends on
`agent_client_protocol ~> 0.1.0` from Hex.

The publishable package has been checked with `mix hex.build`; the Hex
artifact includes the root Elixir package, public docs, notebook, spec,
and package metadata, not the cutover notes or removed legacy code.

Generated docs have been checked with `mix docs`.

## Next Runtime Slices

1. Repo-context gates and file citation support.
2. Large observation artifact storage.
3. Child-call budget wards.
4. First-class council/review-round runtime.
5. Loom retrieval and indexing.
6. SPEC MUST coverage report.
7. ACP compatibility test expansion.
8. Conformance gap report for unsupported `tests.yaml` expectation keys.
9. Explicit safety-contract decision for unrestricted default code
   medium versus sandbox-by-default.

## Release Gate

From the repository root:

```bash
mix verify
scripts/conformance.sh
mix docs
mix hex.build
```

The main gate checks formatting, warnings-as-errors compilation, tests,
and Credo warnings/errors for the canonical implementation. The
conformance script checks the shared YAML contract through the canonical
Elixir suite. The docs and Hex build gates check the package surface.
