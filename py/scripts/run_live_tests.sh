#!/usr/bin/env bash
set -euo pipefail

# Auto-load local env file when present.
if [[ -f ".env" ]]; then
  # shellcheck disable=SC1091
  set -a; source .env; set +a
fi

if [[ "${CANTRIP_INTEGRATION_LIVE:-}" != "1" ]]; then
  echo "Set CANTRIP_INTEGRATION_LIVE=1 to run live tests."
  exit 2
fi

if [[ -z "${CANTRIP_OPENAI_MODEL:-}" ]]; then
  echo "Missing CANTRIP_OPENAI_MODEL"
  exit 2
fi

if [[ -z "${CANTRIP_OPENAI_BASE_URL:-}" ]]; then
  echo "Missing CANTRIP_OPENAI_BASE_URL"
  exit 2
fi

if command -v uv >/dev/null 2>&1; then
  exec uv run pytest -q tests/test_integration_openai_compat_live.py "$@"
fi

exec ./.venv/bin/pytest -q tests/test_integration_openai_compat_live.py "$@"
