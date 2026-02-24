#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${PYTHON:-}" ]]; then
  PY_CMD=("${PYTHON}")
elif command -v uv >/dev/null 2>&1; then
  PY_CMD=(uv run python)
else
  PY_CMD=(./.venv/bin/python)
fi

if [[ $# -gt 0 ]]; then
  for mod in "$@"; do
    "${PY_CMD[@]}" -m "examples.patterns.${mod}"
  done
  exit 0
fi

for file in examples/patterns/*.py; do
  base="$(basename "$file" .py)"
  if [[ "$base" == "__init__" || "$base" == "common" ]]; then
    continue
  fi
  "${PY_CMD[@]}" -m "examples.patterns.${base}"
done
