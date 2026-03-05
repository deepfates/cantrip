# Grimoire Teaching Examples

12 examples following the grimoire progression (SPEC.md Appendix A).

## Run tests

```bash
cd py && uv run pytest tests/patterns/test_grimoire_examples.py -q
```

## Run a single example

```bash
cd py && uv run python -m examples.patterns.01_llm_query
```

Each module exposes `run(llm=None)` and returns a dict with pattern results and metadata.
Set `CANTRIP_OPENAI_MODEL` and `CANTRIP_OPENAI_BASE_URL` env vars for real LLM mode;
otherwise falls back to FakeLLM with scripted responses.
