#!/usr/bin/env bash
set -euo pipefail

PY="${PYTHON:-./.venv/bin/python}"

if [[ $# -gt 0 ]]; then
  for mod in "$@"; do
    "$PY" -m "examples.patterns.${mod}"
  done
  exit 0
fi

for file in examples/patterns/*.py; do
  base="$(basename "$file" .py)"
  if [[ "$base" == "__init__" || "$base" == "common" ]]; then
    continue
  fi
  "$PY" -m "examples.patterns.${base}"
done
