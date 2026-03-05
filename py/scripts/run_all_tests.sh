#!/usr/bin/env bash
set -euo pipefail

./scripts/run_nonlive_tests.sh "$@"

if [[ "${CANTRIP_INTEGRATION_LIVE:-}" == "1" ]]; then
  ./scripts/run_live_tests.sh "$@"
else
  echo "Skipping live tests (set CANTRIP_INTEGRATION_LIVE=1 to enable)."
fi
