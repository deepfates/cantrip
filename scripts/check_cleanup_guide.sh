#!/usr/bin/env bash
# Cleanup-guide regression gate.
#
# Asserts that the patterns the cleanup pass eliminated have not been
# reintroduced. Each `fail_if_new_unallowed` declares a pattern + the
# explicit allowlisted files where the pattern is legitimate (bounded by
# upstream policy). New occurrences anywhere else fail CI.
#
# The intent is to make the cleanup pass *durable*: if a future commit adds
# `String.to_atom(user_input)` to a non-allowlisted file, this gate fires
# before the regression ships.
#
# See `docs/cleanup-status.md` for the pass ledger this gate protects.

set -euo pipefail

# Scan only production code by default. Tests are allowed to exercise the
# patterns deliberately as part of red-team / regression coverage.
SCAN_DIRS="lib"

fail_count=0

# fail_if_new_unallowed <ripgrep-pattern> <message> <allowed-file...>
#
# Greps SCAN_DIRS for the pattern, filters out lines whose file is in the
# allowlist, and fails if anything remains. Each allowed file is a partial
# path match (substring); use a specific path tail (e.g.
# `gate/compile_and_load.ex`) to keep the allowlist tight.
fail_if_new_unallowed() {
  local pattern="$1"
  local message="$2"
  shift 2

  local hits
  hits=$(grep -RnE --include='*.ex' "$pattern" $SCAN_DIRS 2>/dev/null || true)

  if [[ -z "$hits" ]]; then
    return 0
  fi

  local filtered="$hits"
  for allowed in "$@"; do
    filtered=$(echo "$filtered" | grep -v "$allowed" || true)
  done

  if [[ -n "$filtered" ]]; then
    echo "FAIL: $message"
    echo "$filtered"
    echo
    fail_count=$((fail_count + 1))
  fi
}

# --- Pass 3: atom safety ---------------------------------------------------
# `String.to_atom` is only allowed where the input is bounded upstream:
#   - compile_and_load: name is validated against exact allowlist first
#   - familiar.ex / familiar/cookie.ex: workspace fingerprint / random tail
fail_if_new_unallowed \
  'String\.to_atom\b' \
  'unbounded String.to_atom found (Pass 3 atom-safety regression)' \
  'lib/cantrip/gate/compile_and_load.ex' \
  'lib/cantrip/familiar.ex' \
  'lib/cantrip/familiar/cookie.ex' \
  'lib/mix/tasks/cantrip.familiar.ex' \
  'lib/cantrip/loom/storage/jsonl.ex'

# --- Pass 6: unsafe deserialization / runtime eval -------------------------
# `binary_to_term` without `[:safe]` is the unsafe shape. We use the safe
# variant via Cantrip.Medium.Code.Port.safe_binary_to_term/2. The one
# exception is port_child.ex:786 (parent→child direction, parent is the
# trusted side; comment in source explains why [:safe] would over-reject).
fail_if_new_unallowed \
  ':erlang\.binary_to_term\([^,)]+\)' \
  'binary_to_term without [:safe] found (Pass 6 deserialization regression)' \
  'lib/cantrip/medium/code/port_child.ex'

# `Code.eval_string` is never allowed in lib/.
fail_if_new_unallowed \
  'Code\.eval_string' \
  'Code.eval_string found (Pass 6 runtime-eval regression)'

# `Code.eval_quoted` is allowed in:
#   - port_child.ex (sandboxed child BEAM evaluator)
#   - medium/code.ex (the explicit `:unrestricted` escape hatch for trusted
#     local dev — see sandbox option documentation in port-isolated-runtime.md)
fail_if_new_unallowed \
  'Code\.eval_quoted' \
  'Code.eval_quoted found outside sandbox boundaries (Pass 6 regression)' \
  'lib/cantrip/medium/code/port_child.ex' \
  'lib/cantrip/medium/code.ex'

# `Code.compile_string` is only allowed in the gated hot-load path.
fail_if_new_unallowed \
  'Code\.compile_string' \
  'Code.compile_string found outside compile_and_load (Pass 6 regression)' \
  'lib/cantrip/gate/compile_and_load.ex'

# --- Pass 4: ambient configuration / authority -----------------------------
# `System.get_env` / `Application.get_env` are only allowed in boot/config
# paths. Hot-path reads of env are forbidden.
fail_if_new_unallowed \
  'System\.get_env|System\.put_env' \
  'System.get_env/put_env in hot path (Pass 4 ambient-authority regression)' \
  'lib/cantrip/application.ex' \
  'lib/cantrip/llm.ex' \
  'lib/mix/tasks/cantrip.familiar.ex'

# --- Pass 7: bare process spawning -----------------------------------------
# Bare `spawn` is forbidden — use Task.Supervisor.start_child or document
# the supervision strategy in docs/architecture.md Process Inventory.
fail_if_new_unallowed \
  '\bspawn\s*\(' \
  'bare spawn found (Pass 7 supervision regression)'

# `spawn_link` is only allowed in the port-child bootstrap.
fail_if_new_unallowed \
  '\bspawn_link\s*\(' \
  'bare spawn_link found outside port-child bootstrap (Pass 7 regression)' \
  'lib/cantrip/medium/code/port_child.ex'

# --- Result ----------------------------------------------------------------
if (( fail_count > 0 )); then
  echo "cleanup-guide regression gate failed ($fail_count violation set(s))"
  echo "see docs/cleanup-status.md"
  exit 1
fi

echo "cleanup-guide regression gate passed"
