# Real Crystal Testing

Use this to run integration tests against real OpenAI-compatible endpoints
(hosted APIs or local model servers).

## Env vars

- `CANTRIP_INTEGRATION_LIVE=1`
- `CANTRIP_OPENAI_MODEL=<model-name>`
- `CANTRIP_OPENAI_BASE_URL=<base-url>` (for example `http://localhost:11434/v1`)
- `CANTRIP_OPENAI_API_KEY=<key>` (optional for some local servers)

You can set these in a local `.env` file. The integration test module and
`scripts/run_live_tests.sh` both auto-load `.env` when present.

## Run

```bash
CANTRIP_INTEGRATION_LIVE=1 \
CANTRIP_OPENAI_MODEL=<model> \
CANTRIP_OPENAI_BASE_URL=<url> \
./scripts/run_live_tests.sh
```

Or run pytest directly:

```bash
uv run pytest -q tests/test_integration_openai_compat_live.py
```

The tests are skipped unless `CANTRIP_INTEGRATION_LIVE=1` is set.
