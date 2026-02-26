from __future__ import annotations

import json

from cantrip import Cantrip, Circle, FakeCrystal
from cantrip.cli_runner import format_cli_json, run_cli


def test_cli_runner_matches_direct_cast() -> None:
    spec = {"responses": [{"tool_calls": [{"gate": "done", "args": {"answer": "ok"}}]}]}
    direct = Cantrip(
        crystal=FakeCrystal(spec),
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}]),
    )
    via_cli = Cantrip(
        crystal=FakeCrystal(spec),
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}]),
    )
    assert run_cli(via_cli, intent="x")["result"] == direct.cast("x")


def test_cli_json_formatter_emits_valid_json() -> None:
    payload = {"result": "ok", "thread_id": "t1"}
    encoded = format_cli_json(payload)
    decoded = json.loads(encoded)
    assert decoded == payload
