# Ward Policy

This project enforces runtime and medium safety with wards on `circle.wards`.

## Core Composition Wards

- `max-turns` (required): positive integer.
- `max-depth`: positive integer; blocks nested `call-agent` once reached.
- `max-batch-size`: positive integer; upper bound for `call-agent-batch` request count.
- `max-child-calls-per-turn`: positive integer; cap across `call-agent` and `call-agent-batch` within one parent turn.

## Code/Minecraft Execution Wards

- `allow-require`: boolean; defaults to blocked behavior unless explicitly true.
- `max-eval-ms`: positive integer; wall-clock timeout for medium code evaluation.
- `max-forms`: positive integer; max number of forms accepted in one code snippet.

## Recommended Defaults

For production-like use:

- `max-turns`: `10`
- `max-depth`: `1`
- `max-batch-size`: `8`
- `max-child-calls-per-turn`: `8`
- `allow-require`: `false`
- `max-eval-ms`: `250`
- `max-forms`: `20`

For stricter sandboxing:

- `max-depth`: `0` to disable composition.
- `max-batch-size`: `1`
- `max-child-calls-per-turn`: `1`
- `max-eval-ms`: `100`
- `max-forms`: `5`

## Validation Rules

Ward validation happens at cantrip construction:

- integer wards must be positive integers
- boolean wards must be boolean

Invalid ward values fail fast in domain validation.
