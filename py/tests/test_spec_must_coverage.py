from __future__ import annotations

import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent


# Explicitly tracked uncovered MUST rules from SPEC.md.
# This list should only shrink as executable coverage expands.
EXPECTED_UNCOVERED_MUST_RULES: set[str] = set()


def _must_rule_ids_from_spec() -> set[str]:
    spec_lines = (ROOT / "SPEC.md").read_text().splitlines()
    must_ids: set[str] = set()
    for line in spec_lines:
        match = re.search(r">\s*\*\*([A-Z]+-\d+)\*\*:\s*(.*)", line)
        if match and "MUST" in match.group(2):
            must_ids.add(match.group(1))
    return must_ids


def _rule_ids_from_tests_yaml() -> set[str]:
    raw = (ROOT / "tests.yaml").read_text()
    raw = re.sub(
        r"parent_id:\s*(turns\[\d+\]\.id)",
        lambda m: f'parent_id: "{m.group(1)}"',
        raw,
    )
    raw = "\n".join(
        line
        for line in raw.splitlines()
        if "{ utterance: not_null, observation: not_null" not in line
    )
    cases = yaml.safe_load(raw)
    return {str(case["rule"]) for case in cases}


def test_spec_must_rules_are_covered_or_explicitly_tracked() -> None:
    missing = _must_rule_ids_from_spec() - _rule_ids_from_tests_yaml()
    assert missing == EXPECTED_UNCOVERED_MUST_RULES
