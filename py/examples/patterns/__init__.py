"""Grimoire pattern progression examples."""

from __future__ import annotations

import importlib
from types import ModuleType

PATTERN_MODULES: list[str] = [
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
]


def load_pattern(module_name: str) -> ModuleType:
    if module_name not in PATTERN_MODULES:
        raise ValueError(f"unknown pattern module: {module_name}")
    return importlib.import_module(f"{__name__}.{module_name}")


__all__ = ["PATTERN_MODULES", "load_pattern"]
