#!/usr/bin/env bash
set -euo pipefail

# Auto-load local env file when present.
if [[ -f ".env" ]]; then
  # shellcheck disable=SC1091
  set -a; source .env; set +a
fi

if command -v uv >/dev/null 2>&1; then
  exec uv run pytest -q -k 'not integration_openai_compat_live' "$@"
fi

exec ./.venv/bin/pytest -q -k 'not integration_openai_compat_live' "$@"
