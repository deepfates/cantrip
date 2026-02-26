#!/usr/bin/env bash
set -euo pipefail
LOG=${1:-/tmp/cantrip_acp_zed_real.log}
SECS=${2:-90}
for _ in $(seq 1 "$SECS"); do
  if [[ -f "$LOG" ]] && [[ -s "$LOG" ]]; then
    ./scripts/acp_debug_log_summary.py --log "$LOG"
    exit 0
  fi
  sleep 1
done
printf '{"ok":false,"reason":"no real zed acp log yet","log":"%s"}\n' "$LOG"
exit 2
