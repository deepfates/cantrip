from __future__ import annotations

import importlib
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def _load(name: str):
    return importlib.import_module(f"examples.patterns.{name}")


def _force_scripted_mode() -> None:
    os.environ.pop("CANTRIP_OPENAI_MODEL", None)
    os.environ.pop("CANTRIP_OPENAI_BASE_URL", None)


def test_01_llm_query_scripted() -> None:
    _force_scripted_mode()
    out = _load("01_llm_query").run()
    assert out["pattern"] == 1
    assert out["message_count"] == 1
    assert out["stateless"] is True


def test_02_gate_scripted() -> None:
    _force_scripted_mode()
    out = _load("02_gate").run()
    assert out["pattern"] == 2
    assert out["echo_result"] == "hello from gate"
    assert out["done_rejects_empty"] is True


def test_03_circle_scripted() -> None:
    _force_scripted_mode()
    out = _load("03_circle").run()
    assert out["pattern"] == 3
    assert "done" in out["gates"]
    assert out["missing_done_error"] is not None
    assert out["missing_ward_error"] is not None


def test_04_cantrip_scripted() -> None:
    _force_scripted_mode()
    out = _load("04_cantrip").run()
    assert out["pattern"] == 4
    assert out["independent_threads"] is True
    assert out["turn_counts"] == [1, 1]


def test_05_wards_scripted() -> None:
    _force_scripted_mode()
    out = _load("05_wards").run()
    assert out["pattern"] == 5
    assert out["child_terminated"] is True
    assert out["max_turns_min_wins"] is True
    assert out["require_done_or"] is True


def test_06_medium_scripted() -> None:
    _force_scripted_mode()
    out = _load("06_medium").run()
    assert out["pattern"] == 6
    assert out["tool_surface"] == ["done"]
    assert out["code_surface"] == ["code"]
    assert "done" in out["code_observation_gates"]


def test_07_full_agent_scripted() -> None:
    _force_scripted_mode()
    out = _load("07_full_agent").run()
    assert out["pattern"] == 7
    assert out["turn_count"] == 3
    assert out["terminated"] is True
    assert out["first_error"] is True
    assert out["adapted_with_second_read"] is True


def test_08_folding_scripted() -> None:
    _force_scripted_mode()
    out = _load("08_folding").run()
    assert out["pattern"] == 8
    assert out["turn_count"] == 4
    assert out["folded_context_seen"] is True
    assert out["identity_preserved"] is True


def test_09_composition_scripted() -> None:
    _force_scripted_mode()
    out = _load("09_composition").run()
    assert out["pattern"] == 9
    assert out["child_threads"] == 2
    assert out["batch_result_count"] == 2


def test_10_loom_scripted() -> None:
    _force_scripted_mode()
    out = _load("10_loom").run()
    assert out["pattern"] == 10
    assert out["thread_count"] == 2
    assert out["turn_count"] == 2
    assert out["terminated"] is True
    assert out["truncated"] is True
    assert out["total_tokens"][0] > 0


def test_11_persistent_entity_scripted() -> None:
    _force_scripted_mode()
    out = _load("11_persistent_entity").run()
    assert out["pattern"] == 11
    assert out["accumulated_turns"] >= 2
    assert out["last_thread_turns"] >= 2
    assert out["remembers_prior_turn"] is True


def test_12_familiar_scripted() -> None:
    _force_scripted_mode()
    out = _load("12_familiar").run()
    assert out["pattern"] == 12
    assert out["loom_threads"] >= 6
    assert out["entity_turns"] >= 2
    assert out["persisted_loom"] is True
    assert out["child_code_calls"] >= 2
    assert out["child_tool_calls"] >= 2
