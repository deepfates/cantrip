#!/usr/bin/env bash
set -euo pipefail

if [[ -f ".env" ]]; then
  # shellcheck disable=SC1091
  set -a; source .env; set +a
fi

if [[ -n "${PYTHON:-}" ]]; then
  PY="${PYTHON}"
  USE_UV=0
  RUNNER=("${PY}")
elif command -v uv >/dev/null 2>&1; then
  PY="${PYTHON:-python}"
  USE_UV=1
  RUNNER=(uv run python)
else
  PY="./.venv/bin/python"
  USE_UV=0
  RUNNER=("${PY}")
fi
REPO_ROOT="${1:-.}"
PROMPT_TEXT="${2:-hi}"

"${RUNNER[@]}" - <<'PY' "$PY" "$REPO_ROOT" "$PROMPT_TEXT" "$USE_UV"
import json
import subprocess
import sys
import time

py = sys.argv[1]
repo_root = sys.argv[2]
prompt_text = sys.argv[3]
use_uv = sys.argv[4] == "1"
if use_uv:
    cmd = ["uv", "run", "python", "scripts/capstone.py", "--fake", "--repo-root", repo_root, "--acp-stdio"]
else:
    cmd = [py, "scripts/capstone.py", "--fake", "--repo-root", repo_root, "--acp-stdio"]
p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
assert p.stdin is not None
assert p.stdout is not None

def send(obj):
    p.stdin.write(json.dumps(obj) + "\n")
    p.stdin.flush()
    line = p.stdout.readline().strip()
    print(line)
    return json.loads(line)

send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": 1}})
new = send(
    {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "session/new",
        "params": {"cwd": repo_root, "mcpServers": []},
    }
)
sid = new["result"]["sessionId"]
p.stdin.write(
    json.dumps(
        {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "session/prompt",
            "params": {"sessionId": sid, "prompt": [{"type": "text", "text": prompt_text}]},
        }
    )
    + "\n"
)
p.stdin.flush()

# Updates can vary by transport and model behavior. Read until prompt response id=3 arrives.
deadline = time.time() + 20.0
got_prompt_result = False
while time.time() < deadline:
    raw = p.stdout.readline()
    if not raw:
        break
    line = raw.strip()
    if not line:
        continue
    print(line)
    try:
        msg = json.loads(line)
    except Exception:
        continue
    if msg.get("id") == 3 and "result" in msg:
        got_prompt_result = True
        break

if not got_prompt_result:
    raise SystemExit("did not receive prompt response (id=3) within timeout")

p.terminate()
PY
