# Interactive Capstone Agent

This repo includes an entity CLI that can:

- inspect repository files via `repo_files` and `repo_read`
- delegate with `call_entity` and `call_entity_batch`
- run in `text`, `code`, or `browser` medium
- run in ACP stdio mode or a local REPL

## Required env

- `CANTRIP_OPENAI_MODEL`
- `CANTRIP_OPENAI_BASE_URL`
- `CANTRIP_OPENAI_API_KEY` (optional for some local servers)

Both scripts auto-load `.env` by default.

## Verification

Run the non-live suite:

```bash
./scripts/run_nonlive_tests.sh
```

Run the default full check (non-live always; live when enabled):

```bash
./scripts/run_all_tests.sh
```

Run live provider integration tests (requires configured live model env):

```bash
CANTRIP_INTEGRATION_LIVE=1 ./scripts/run_live_tests.sh
```

## Medium runtime configuration

- `CANTRIP_CAPSTONE_MEDIUM=text|code|browser`
- `CANTRIP_CAPSTONE_CODE_RUNNER=mini|python-subprocess` (for code medium)
- `CANTRIP_CAPSTONE_CODE_TIMEOUT_S=5` (for subprocess code runner)
- `CANTRIP_CAPSTONE_BROWSER_DRIVER=memory|playwright` (for browser medium)

Equivalent CLI flags:

- `--code-runner mini|python-subprocess`
- `--browser-driver memory|playwright`

Canonical entrypoint:

```bash
uv run python scripts/capstone.py
```

Installed entrypoint (preferred after package install):

```bash
cantrip
```

Default mode is pipe (stdin intents -> JSONL output).

## Pipe (default)

```bash
printf "list files\nread cantrip/runtime.py\n" | \
  uv run python scripts/capstone.py --repo-root . --with-events
```

Equivalent subcommand form:

```bash
printf "list files\n" | cantrip --repo-root . pipe
```

Offline smoke test (no model/API):

```bash
printf "hello\n" | \
  uv run python scripts/capstone.py --repo-root . --fake
```

## REPL

```bash
uv run python scripts/capstone.py --repl --repo-root .
```

Type intents directly. Exit with `:q`.

### Browser medium with Playwright

Install browser runtime once:

```bash
uv add --optional browser playwright
uv run playwright install chromium
```

Run with browser medium:

```bash
CANTRIP_CAPSTONE_MEDIUM=browser \
CANTRIP_CAPSTONE_BROWSER_DRIVER=playwright \
uv run python scripts/capstone.py --repl --repo-root .
```

## ACP stdio server

```bash
uv run python scripts/capstone.py --acp-stdio --repo-root .
```

Subcommand form:

```bash
cantrip --repo-root . acp-stdio
```

Then send newline-delimited JSON-RPC requests:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1}}
{"jsonrpc":"2.0","id":2,"method":"session/new","params":{}}
{"jsonrpc":"2.0","id":3,"method":"session/prompt","params":{"sessionId":"<session-id>","prompt":[{"type":"text","text":"List Python files and read cantrip/runtime.py"}]}}
```

Or run a built-in smoke check:

```bash
./scripts/smoke_acp.sh . "hello"
```
