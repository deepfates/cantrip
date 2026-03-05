"""Structural tests for grimoire teaching examples.

These tests verify that each example demonstrates its pattern correctly,
regardless of LLM output. They test structure, not content.

Cross-cutting requirement: every example supports two modes:
  - run(mode="scripted") -> uses FakeLLM, deterministic, CI-safe
  - run()               -> loads .env, uses real LLM, raises if no keys

Silent fallbacks are forbidden. If env vars are missing and mode is not
"scripted", the example MUST raise, not silently use FakeLLM.
"""

from __future__ import annotations

import importlib
import os
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def _load(name: str):
    mod_name = f"examples.patterns.{name}"
    if mod_name in sys.modules:
        return importlib.reload(sys.modules[mod_name])
    return importlib.import_module(mod_name)


_ENV_PREFIXES = ("CANTRIP_", "OPENAI_", "ANTHROPIC_", "GOOGLE_", "LM_STUDIO_")

# Path to the .env file that examples load via load_dotenv_if_present
_DOTENV_PATH = ROOT / ".env"


def _clean_env() -> None:
    """Remove ALL cantrip/openai/anthropic env vars so we can test the no-env-vars path."""
    for key in list(os.environ):
        if key.startswith(_ENV_PREFIXES):
            del os.environ[key]


# ── Cross-cutting: no silent fallbacks ────────────────────────────────────────


class TestNoSilentFallbacks:
    """If env vars are missing and .env is absent, examples must raise (not silently use FakeLLM)."""

    @pytest.fixture(autouse=True)
    def _hide_dotenv_and_clean(self, tmp_path):
        """Temporarily rename .env so examples can't load it, and strip env vars."""
        _clean_env()
        hidden = _DOTENV_PATH.with_suffix(".env.hidden")
        had_dotenv = _DOTENV_PATH.exists()
        if had_dotenv:
            _DOTENV_PATH.rename(hidden)
        yield
        if had_dotenv and hidden.exists():
            hidden.rename(_DOTENV_PATH)
        _clean_env()

    @pytest.mark.parametrize(
        "name",
        [
            "01_llm_query",
            "04_cantrip",
            "05_wards",
            "06_medium",
            "07_full_agent",
            "09_composition",
            "10_loom",
            "11_persistent_entity",
            "12_familiar",
        ],
    )
    def test_no_env_no_scripted_raises(self, name: str) -> None:
        mod = _load(name)
        with pytest.raises((RuntimeError, KeyError, ValueError)):
            mod.run()


# ── Cross-cutting: mode="scripted" always works ──────────────────────────────


class TestScriptedModeWorks:
    """mode='scripted' must use FakeLLM and succeed without env vars."""

    @pytest.fixture(autouse=True)
    def _clean(self):
        _clean_env()
        yield
        _clean_env()

    @pytest.mark.parametrize(
        "name",
        [
            "01_llm_query",
            "02_gate",
            "03_circle",
            "04_cantrip",
            "05_wards",
            "06_medium",
            "07_full_agent",
            "08_folding",
            "09_composition",
            "10_loom",
            "11_persistent_entity",
            "12_familiar",
        ],
    )
    def test_scripted_mode_succeeds(self, name: str) -> None:
        mod = _load(name)
        out = mod.run(mode="scripted")
        assert isinstance(out, dict), f"{name} run(mode='scripted') must return a dict"
        assert "pattern" in out, f"{name} must include 'pattern' key"


# ── Per-example structural requirements (scripted mode) ──────────────────────


class TestPatternStructure:
    """Structural requirements per pattern, run in scripted mode."""

    @pytest.fixture(autouse=True)
    def _clean(self):
        _clean_env()
        yield
        _clean_env()

    def test_01_llm_query(self) -> None:
        out = _load("01_llm_query").run(mode="scripted")
        assert out["pattern"] == 1
        assert out["message_count"] == 1, "must send exactly one message"
        assert out["stateless"] is True, "must declare itself stateless"
        assert isinstance(out["result"], str), "result must be a string"

    def test_02_gate(self) -> None:
        out = _load("02_gate").run(mode="scripted")
        assert out["pattern"] == 2
        assert "echo" in out["gate_names"], "echo gate must be visible"
        assert "done" in out["gate_names"], "done gate must be visible"
        assert out["done_rejects_empty"] is True, "done must reject empty answer"

    def test_03_circle(self) -> None:
        out = _load("03_circle").run(mode="scripted")
        assert out["pattern"] == 3
        assert "done" in out["gates"], "valid circle has done"
        assert out["missing_done_error"] is not None, "Circle() must reject no done"
        assert out["missing_ward_error"] is not None, "Circle() must reject no ward"

    def test_04_cantrip(self) -> None:
        out = _load("04_cantrip").run(mode="scripted")
        assert out["pattern"] == 4
        assert out["independent_threads"] is True, "two casts must produce different thread IDs"
        assert len(out["thread_ids"]) == 2
        assert all(isinstance(tid, str) for tid in out["thread_ids"])

    def test_05_wards(self) -> None:
        out = _load("05_wards").run(mode="scripted")
        assert out["pattern"] == 5
        assert out["child_terminated"] is True, "child thread must terminate"
        assert out["max_turns_min_wins"] is True, "min of max_turns must win"

    def test_06_medium(self) -> None:
        out = _load("06_medium").run(mode="scripted")
        assert out["pattern"] == 6
        assert "done" in out["tool_surface"], "tool medium must expose done"
        assert "code" in out["code_surface"], "code medium must expose code"

    def test_07_full_agent(self) -> None:
        out = _load("07_full_agent").run(mode="scripted")
        assert out["pattern"] == 7
        assert out["terminated"] is True, "agent must terminate"
        assert out["had_error"] is True, "agent must encounter an error"
        assert out["error_then_recovery"] is True, "agent must recover after error"
        assert out["turn_count"] >= 2, "need at least 2 turns for error+recovery"

    def test_08_folding(self) -> None:
        out = _load("08_folding").run(mode="scripted")
        assert out["pattern"] == 8
        assert out["folded_context_seen"] is True, "folding marker must appear in context"
        assert out["identity_preserved"] is True, "identity must never be folded"
        assert out["turn_count"] >= 3, "need enough turns to trigger folding"

    def test_09_composition(self) -> None:
        out = _load("09_composition").run(mode="scripted")
        assert out["pattern"] == 9
        assert out["child_threads"] >= 1, "parent must delegate to at least one child"
        assert out["batch_result_count"] >= 1, "batch must produce results"

    def test_10_loom(self) -> None:
        out = _load("10_loom").run(mode="scripted")
        assert out["pattern"] == 10
        assert out["thread_count"] >= 1, "loom must have threads"
        assert out["turn_count"] >= 1, "loom must have turns"
        assert out["terminated"] is True, "at least one thread must terminate"
        assert out["truncated"] is True, "at least one thread must be truncated"
        assert out["total_tokens"][0] > 0, "token counts must be positive"

    def test_11_persistent_entity(self) -> None:
        out = _load("11_persistent_entity").run(mode="scripted")
        assert out["pattern"] == 11
        assert out["accumulated_turns"] >= 2, "entity needs 2+ sends"
        assert out["last_thread_turns"] >= 1, "last send must produce turns"

    def test_12_familiar(self) -> None:
        out = _load("12_familiar").run(mode="scripted")
        assert out["pattern"] == 12
        assert out["loom_threads"] >= 2, "familiar must spawn child threads"
        assert out["entity_turns"] >= 2, "familiar must do 2+ sends"
        assert out["persisted_loom"] is True, "loom must persist to disk"
