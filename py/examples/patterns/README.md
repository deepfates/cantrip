# Pattern Examples

Run all examples through tests:

```bash
pytest -q tests/patterns/test_pattern_examples.py
```

Run all pattern modules directly:

```bash
bash scripts/run_patterns.sh
```

Run one or more specific patterns:

```bash
bash scripts/run_patterns.sh 01_primitive_loop 16_familiar_pattern
```

Each module exposes `run()` and returns a small dictionary describing the pattern result.
