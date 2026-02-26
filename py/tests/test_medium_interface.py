from __future__ import annotations

from cantrip.mediums import BrowserMedium, CodeMedium, ToolMedium, medium_for
from cantrip.models import Circle


def test_medium_factory_returns_tool_medium_by_default() -> None:
    circle = Circle(gates=["done"], wards=[{"max_turns": 1}], medium="tool")
    medium = medium_for(circle.medium)
    assert isinstance(medium, ToolMedium)


def test_medium_factory_returns_code_medium() -> None:
    medium = medium_for("code")
    assert isinstance(medium, CodeMedium)


def test_medium_factory_returns_browser_medium() -> None:
    medium = medium_for("browser")
    assert isinstance(medium, BrowserMedium)


def test_tool_medium_projects_circle_gates() -> None:
    circle = Circle(
        gates=[
            "done",
            {"name": "echo", "parameters": {"type": "object", "properties": {}}},
        ],
        wards=[{"max_turns": 1}],
    )
    tools = ToolMedium().make_tools(circle)
    assert [t["name"] for t in tools] == ["done", "echo"]


def test_code_medium_projects_single_code_tool_and_requires_code_arg() -> None:
    circle = Circle(gates=["done"], wards=[{"max_turns": 1}], medium="code")
    tools = CodeMedium().make_tools(circle)
    assert [t["name"] for t in tools] == ["code"]
    assert tools[0]["parameters"]["required"] == ["code"]


def test_code_medium_normalizes_tool_choice_to_required() -> None:
    assert CodeMedium().tool_choice(None) == "required"
    assert CodeMedium().tool_choice("required") == "required"
