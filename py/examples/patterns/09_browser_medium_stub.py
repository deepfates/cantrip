from __future__ import annotations

from .common import mk_basic_cantrip


def run():
    cantrip = mk_basic_cantrip(
        [
            {
                "tool_calls": [
                    {
                        "gate": "browser",
                        "args": {"action": "open", "url": "https://example.com"},
                    },
                    {"gate": "done", "args": {"answer": "ok"}},
                ]
            }
        ],
        gates=["done"],
        medium="browser",
    )
    result, thread = cantrip.cast_with_thread("open home page")
    return {
        "pattern": 9,
        "medium": "browser",
        "result": result,
        "url": thread.turns[0].observation[0].result["url"],
    }
