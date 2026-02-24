# Pattern Progression

This curriculum maps concrete cantrip examples to increasingly complex operating patterns.
Each pattern keeps the same core nouns (crystal, call, circle, intent, loom) and only adds one major capability at a time.

## Pattern Map

| Pattern | Focus | Spec anchors | Practical outcome |
|---|---|---|---|
| 01 | Primitive loop | LOOP-1/2/3, CANTRIP-1 | Minimal cast with done + max_turns |
| 02 | Done vs truncation | LOOP-4/6, LOOM-7 | Distinguish terminated and truncated runs |
| 03 | Crystal contract | CRYSTAL-3/4/5/6 | Validate content/tools and provider normalization |
| 04 | Circle invariants | CIRCLE-1/2, CALL-3 | Validate gates + wards before execution |
| 05 | Ward policies | CIRCLE-6, LOOP-2 | Remove/limit gates through wards |
| 06 | Provider portability | CrystalProvider | Swap crystal by configuration |
| 07 | Conversation medium | Medium: conversation | Tool-calling baseline medium |
| 08 | Code medium | Medium: js/code, CIRCLE-9 | Stateful code execution across turns |
| 09 | Browser medium | Medium viewport principle | Executable browser action loop via browser driver |
| 10 | Batch delegation | COMP-3, LOOM-8 | Parallel children, deterministic ordering |
| 11 | Folding | LOOM-5, CALL-5, PROD-4 | Compress working context, preserve loom history |
| 12 | Full code agent | CIRCLE, wards, gate deps | Filesystem access via gates with safeguards |
| 13 | Service wrapper | Production interface | Cantrip exposed as callable service boundary |
| 14 | Recursive delegation | COMP-6, max_depth | Safe recursive child creation |
| 15 | Research orchestration | call_entity_batch + mediums | Multi-step decomposition pattern |
| 16 | Familiar pattern | persistent loom + cantrip-gates | Long-lived coordinator that spawns sub-cantrips |

## How To Read The Examples

Each example provides:
- What changed relative to the prior pattern
- Which spec terms are being exercised
- A tiny runnable `run()` function for smoke tests

## Operational Checklist

1. Validate circle invariants (`done`, truncation ward) at construction.
2. Pick one medium per circle and document its physics.
3. Resolve wards and publish limits to telemetry.
4. Add delegation only when needed; cap depth.
5. Fold context before provider limits; keep loom append-only.
6. Persist loom when continuity is needed.
