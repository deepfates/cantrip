"""Protocol surface adapters.

All three adapters (CLI, HTTP, ACP) are intentionally transparent wrappers
around ``cantrip.cast()``.  They exist so that protocol-specific behaviour
can be added later without changing call sites.
"""

from __future__ import annotations

from cantrip.runtime import Cantrip


def _cast_adapter(cantrip: Cantrip, intent: str):
    """Shared implementation — a transparent cast wrapper."""
    return cantrip.cast(intent)


# Public aliases kept for backward compatibility and __init__ exports.
cast_via_cli = _cast_adapter
cast_via_http = _cast_adapter
cast_via_acp = _cast_adapter
