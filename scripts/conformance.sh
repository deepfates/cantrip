#!/usr/bin/env bash
# Run conformance tests across all cantrip implementations
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

# --- TypeScript ---
echo "--- ts (TypeScript/Bun) ---"
cd "$ROOT/ts"
echo "  Running: bun test tests/conformance.test.ts (timeout 180s)"
TS_LOG="$(mktemp)"
if run_with_timeout 180 bun test tests/conformance.test.ts 2>&1 | tee "$TS_LOG"; then
  TS_STATUS=0
else
  TS_STATUS=${PIPESTATUS[0]}
fi
TS_CLEAN="$(mktemp)"
strip_ansi_to_file "$TS_LOG" "$TS_CLEAN"
TS_PASS="$(extract_count "pass" "$TS_CLEAN")"
TS_SKIP="$(extract_count "skip" "$TS_CLEAN")"
TS_FAIL="$(extract_count "fail" "$TS_CLEAN")"
echo "  Summary: pass=$TS_PASS skip=$TS_SKIP fail=$TS_FAIL"
if [[ "$TS_STATUS" -eq 124 ]]; then
  echo "  Timed out after 180s"
elif [[ "$TS_STATUS" -ne 0 ]]; then
  echo "  Exit code: $TS_STATUS"
fi
rm -f "$TS_LOG" "$TS_CLEAN"
echo ""

# --- Clojure ---
echo "--- clj (Clojure) ---"
cd "$ROOT/clj"
echo "  Running: make conformance (timeout 180s)"
CLJ_LOG="$(mktemp)"
if run_with_timeout 180 make conformance 2>&1 | tee "$CLJ_LOG"; then
  CLJ_STATUS=0
else
  CLJ_STATUS=${PIPESTATUS[0]}
fi
CLJ_RESULT="$(grep -E "^(YAML|Batch|Ran )" "$CLJ_LOG" || true)"
if [[ -n "$CLJ_RESULT" ]]; then
  echo "$CLJ_RESULT" | sed 's/^/  /'
fi
if [[ "$CLJ_STATUS" -eq 124 ]]; then
  echo "  Timed out after 180s"
elif [[ "$CLJ_STATUS" -ne 0 ]]; then
  echo "  Exit code: $CLJ_STATUS"
fi
rm -f "$CLJ_LOG"
echo ""

# --- Elixir ---
echo "--- ex (Elixir) ---"
cd "$ROOT/ex"
echo "  Running: mix test (timeout 180s)"
EX_LOG="$(mktemp)"
if run_with_timeout 180 mix test 2>&1 | tee "$EX_LOG"; then
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

# --- Python ---
echo "--- py (Python) ---"
cd "$ROOT/py"
echo "  Running: uv run pytest tests/test_conformance.py -q (timeout 180s)"
PY_LOG="$(mktemp)"
if run_with_timeout 180 uv run pytest tests/test_conformance.py -q 2>&1 | tee "$PY_LOG"; then
  PY_STATUS=0
else
  PY_STATUS=${PIPESTATUS[0]}
fi
PY_RESULT="$(tail -1 "$PY_LOG" || true)"
if [[ -n "$PY_RESULT" ]]; then
  echo "  $PY_RESULT"
fi
if [[ "$PY_STATUS" -eq 124 ]]; then
  echo "  Timed out after 180s"
elif [[ "$PY_STATUS" -ne 0 ]]; then
  echo "  Exit code: $PY_STATUS"
fi
rm -f "$PY_LOG"
echo ""

echo "=== Done ==="
