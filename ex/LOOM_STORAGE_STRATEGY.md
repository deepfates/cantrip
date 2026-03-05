# Loom Storage Strategy

This document defines operational storage guidance for loom persistence.

## Supported Adapters

1. `Memory` (`Cantrip.Loom.Storage.Memory`)
2. `JSONL` (`{:jsonl, path}`)
3. `DETS` (`{:dets, path}`)
4. `Mnesia` (`{:mnesia, %{table: ...}}`) when runtime support is available
5. `Auto` (`{:auto, %{dets_path: ...}}`) prefers Mnesia and falls back to DETS

All adapters preserve append-only turn history semantics.

## Environment Guidance

1. Local dev:
   - `Memory` for speed
   - `JSONL` for inspectable traces
2. Single-node durable dev/test:
   - `DETS` (file-backed)
3. BEAM-native DB runtime:
   - `Mnesia` when available in target runtime
4. Lightweight flexible default:
   - `Auto` to avoid hard dependency on Mnesia availability
5. Production/distributed:
   - Prefer a centrally managed DB-backed adapter with explicit backup/retention policy.

## Runtime Capability Detection

`Mnesia` support is optional at runtime. If unavailable, cantrip falls back to configured alternatives.

## Recommended Progression

1. Use `JSONL`/`DETS` for deterministic local traceability.
2. Validate operational requirements (retention, querying, backup).
3. Introduce/operate a production DB adapter aligned with deployment topology.
