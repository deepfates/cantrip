from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "run_patterns.sh"


def test_run_patterns_script_accepts_explicit_pattern_list() -> None:
    subprocess.run(
        ["bash", str(SCRIPT), "01_primitive_loop", "02_done_vs_truncated"],
        cwd=str(ROOT),
        env={"PYTHON": sys.executable},
        check=True,
    )
