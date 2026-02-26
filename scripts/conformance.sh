#!/usr/bin/env bash
# Run conformance tests across all cantrip implementations
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
SKIP=0

echo "=== Cantrip Conformance Suite ==="
echo "tests.yaml: $(wc -l < "$ROOT/tests.yaml") lines"
echo ""

# --- TypeScript ---
echo "--- ts (TypeScript/Bun) ---"
echo "  No conformance runner yet (uses bun test, not tests.yaml)"
echo "  Unit tests:"
cd "$ROOT/ts"
RESULT=$(bun test 2>&1 | tail -3)
echo "  $RESULT"
echo ""

# --- Clojure ---
echo "--- clj (Clojure) ---"
cd "$ROOT/clj"
RESULT=$(make conformance 2>&1 | grep -E "^(YAML|Batch|Ran )")
echo "  $RESULT"
echo ""

# --- Elixir ---
echo "--- ex (Elixir) ---"
cd "$ROOT/ex"
RESULT=$(mix test 2>&1 | grep -E "(tests|failures)")
echo "  $RESULT"
echo ""

# --- Python ---
echo "--- py (Python) ---"
cd "$ROOT/py"
RESULT=$(uv run pytest tests/test_conformance.py -q 2>&1 | tail -1)
echo "  $RESULT"
echo ""

echo "=== Done ==="
