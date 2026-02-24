from __future__ import annotations

import builtins

import pytest

from cantrip.browser import (
    InMemoryBrowserDriver,
    PlaywrightBrowserDriver,
    browser_driver_from_name,
)
from cantrip.errors import CantripError


def test_browser_driver_from_name_resolves_memory_aliases() -> None:
    assert isinstance(browser_driver_from_name("memory"), InMemoryBrowserDriver)
    assert isinstance(browser_driver_from_name("in-memory"), InMemoryBrowserDriver)
    assert isinstance(browser_driver_from_name("fake"), InMemoryBrowserDriver)


def test_browser_driver_from_name_resolves_playwright_alias() -> None:
    assert isinstance(browser_driver_from_name("playwright"), PlaywrightBrowserDriver)
    assert isinstance(browser_driver_from_name("pw"), PlaywrightBrowserDriver)


def test_browser_driver_from_name_rejects_unknown_driver() -> None:
    with pytest.raises(CantripError, match="unknown browser driver"):
        browser_driver_from_name("wat")


def test_playwright_browser_driver_reports_missing_dependency(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    original_import = builtins.__import__

    def fake_import(name, globals=None, locals=None, fromlist=(), level=0):
        if name == "playwright.sync_api":
            raise ImportError("missing playwright")
        return original_import(name, globals, locals, fromlist, level)

    monkeypatch.setattr(builtins, "__import__", fake_import)
    with pytest.raises(RuntimeError, match="playwright is required"):
        PlaywrightBrowserDriver().create_session()
