#!/usr/bin/env bash
set -euo pipefail

if [[ -f ".env" ]]; then
  # shellcheck disable=SC1091
  set -a; source .env; set +a
fi

PY="${PYTHON:-./.venv/bin/python}"
REPO_ROOT="${1:-.}"
PROMPT_TEXT="${2:-hi}"

"$PY" - <<'PY' "$PY" "$REPO_ROOT" "$PROMPT_TEXT"
import json
import subprocess
import sys

py = sys.argv[1]
repo_root = sys.argv[2]
prompt_text = sys.argv[3]
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
new = send({"jsonrpc": "2.0", "id": 2, "method": "session/new", "params": {}})
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
print(p.stdout.readline().strip())
print(p.stdout.readline().strip())
print(p.stdout.readline().strip())
p.terminate()
PY
