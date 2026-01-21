# Testing

## Unit tests (offline)

```bash
bun test
```

## Integration tests (live network)

Integration tests run **by default** if API keys are present in the environment.
Create a `.env` file with any of the following:

```
OPENAI_API_KEY=...
OPENAI_MODEL=gpt-4o-mini

ANTHROPIC_API_KEY=...
ANTHROPIC_MODEL=claude-3-5-sonnet-20240620

GOOGLE_API_KEY=...
GOOGLE_MODEL=gemini-2.0-flash
```

Then run:

```bash
bun test
```

When a key is missing, integration tests for that provider are skipped.
