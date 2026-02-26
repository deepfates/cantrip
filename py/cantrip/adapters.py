from __future__ import annotations

from cantrip.runtime import Cantrip


def cast_via_cli(cantrip: Cantrip, intent: str):
    """CLI protocol surface: intentionally a transparent cast wrapper."""
    return cantrip.cast(intent)


def cast_via_http(cantrip: Cantrip, intent: str):
    """HTTP protocol surface: intentionally a transparent cast wrapper."""
    return cantrip.cast(intent)


def cast_via_acp(cantrip: Cantrip, intent: str):
    """ACP protocol surface: intentionally a transparent cast wrapper."""
    return cantrip.cast(intent)
