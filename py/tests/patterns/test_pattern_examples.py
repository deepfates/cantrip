from __future__ import annotations

import importlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

PATTERNS = [
    ("examples.patterns.01_primitive_loop", 1),
    ("examples.patterns.02_done_vs_truncated", 2),
    ("examples.patterns.03_crystal_contract", 3),
    ("examples.patterns.04_circle_invariants", 4),
    ("examples.patterns.05_ward_policies", 5),
    ("examples.patterns.06_provider_portability", 6),
    ("examples.patterns.07_conversation_medium", 7),
    ("examples.patterns.08_code_medium", 8),
    ("examples.patterns.09_browser_medium_stub", 9),
    ("examples.patterns.10_batch_delegation", 10),
    ("examples.patterns.11_folding", 11),
    ("examples.patterns.12_full_code_agent", 12),
    ("examples.patterns.13_service_wrapper", 13),
    ("examples.patterns.14_recursive_delegation", 14),
    ("examples.patterns.15_research_orchestration", 15),
    ("examples.patterns.16_familiar_pattern", 16),
]


def load(name: str):
    return importlib.import_module(name)


def test_pattern_examples_run(tmp_path):
    for mod_name, number in PATTERNS:
        mod = load(mod_name)
        if number == 16:
            out = mod.run(tmp_path)
        else:
            out = mod.run()
        assert out["pattern"] == number


def test_key_expectations(tmp_path):
    assert load("examples.patterns.01_primitive_loop").run()["result"] == "ok"

    p2 = load("examples.patterns.02_done_vs_truncated").run()
    assert p2["terminated"] is True
    assert p2["truncated"] is True

    assert load("examples.patterns.10_batch_delegation").run()["result"] == "A"
    assert load("examples.patterns.14_recursive_delegation").run()["result"] == "deepest"
    assert load("examples.patterns.16_familiar_pattern").run(tmp_path)["threads"] >= 1
