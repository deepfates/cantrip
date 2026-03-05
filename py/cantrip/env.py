from __future__ import annotations

import os
from pathlib import Path


def load_dotenv_if_present(path: str = ".env", *, override: bool = False) -> bool:
    """Load KEY=VALUE pairs from a dotenv file if present.

    Returns True when a file was found and processed, False otherwise.
    """
    p = Path(path)
    if not p.exists() or not p.is_file():
        return False

    for raw in p.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            continue
        if (value.startswith('"') and value.endswith('"')) or (
            value.startswith("'") and value.endswith("'")
        ):
            value = value[1:-1]
        if override or key not in os.environ:
            os.environ[key] = value
    return True
