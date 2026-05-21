#!/usr/bin/env bash
# Run the canonical Elixir conformance tests.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

pick_timeout_cmd() {
  if command -v timeout >/dev/null 2>&1; then
    echo "timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    echo "gtimeout"
  else
    echo ""
  fi
}

TIMEOUT_BIN="$(pick_timeout_cmd)"

run_with_timeout() {
  local seconds="$1"
  shift
  if [[ -n "$TIMEOUT_BIN" ]]; then
    "$TIMEOUT_BIN" "$seconds" "$@"
  else
    "$@"
  fi
}

strip_ansi_to_file() {
  local input="$1"
  local output="$2"
  sed -E 's/\x1b\[[0-9;]*[[:alpha:]]//g' "$input" > "$output"
}

extract_count() {
  local label="$1"
  local file="$2"
  local count
  count="$(grep -E "^[[:space:]]*[0-9]+[[:space:]]+${label}$" "$file" | tail -1 | grep -Eo '[0-9]+' || true)"
  if [[ -z "$count" ]]; then
    echo "0"
  else
    echo "$count"
  fi
}

echo "=== Cantrip Conformance Suite ==="
echo "tests.yaml: $(wc -l < "$ROOT/tests.yaml") lines"
echo ""

# --- Elixir ---
echo "--- Elixir ---"
cd "$ROOT"
echo "  Running: mix test test/conformance_test.exs (timeout 180s)"
EX_LOG="$(mktemp)"
if run_with_timeout 180 mix test test/conformance_test.exs 2>&1 | tee "$EX_LOG"; then
  EX_STATUS=0
else
  EX_STATUS=${PIPESTATUS[0]}
fi
EX_RESULT="$(grep -E "(tests|failures)" "$EX_LOG" || true)"
if [[ -n "$EX_RESULT" ]]; then
  echo "$EX_RESULT" | sed 's/^/  /'
fi
if [[ "$EX_STATUS" -eq 124 ]]; then
  echo "  Timed out after 180s"
elif [[ "$EX_STATUS" -ne 0 ]]; then
  echo "  Exit code: $EX_STATUS"
fi
rm -f "$EX_LOG"
echo ""

echo "=== Done ==="
