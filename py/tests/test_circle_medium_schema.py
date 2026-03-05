from __future__ import annotations

import pytest

from cantrip.models import Circle


def test_circle_requires_medium_keyword() -> None:
    c = Circle(gates=["done"], wards=[{"max_turns": 1}], medium="tool")
    assert c.medium == "tool"


def test_circle_rejects_legacy_circle_type_keyword() -> None:
    with pytest.raises(TypeError):
        Circle(gates=["done"], wards=[{"max_turns": 1}], circle_type="code")


def test_circle_rejects_legacy_dependencies_keyword() -> None:
    with pytest.raises(TypeError):
        Circle(gates=["done"], wards=[{"max_turns": 1}], dependencies={"code": {}})
