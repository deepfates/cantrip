#!/usr/bin/env bash
set -euo pipefail

# Auto-load local env file when present.
if [[ -f ".env" ]]; then
  # shellcheck disable=SC1091
  set -a; source .env; set +a
fi

exec ./.venv/bin/pytest -q -k 'not integration_openai_compat_live' "$@"
