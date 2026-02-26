from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any

from cantrip.errors import CantripError


class BrowserSession(ABC):
    @abstractmethod
    def open(self, url: str) -> Any:
        raise NotImplementedError

    @abstractmethod
    def click(self, selector: str) -> Any:
        raise NotImplementedError

    @abstractmethod
    def type(self, selector: str, text: str) -> Any:
        raise NotImplementedError

    @abstractmethod
    def text(self, selector: str) -> str:
        raise NotImplementedError

    @abstractmethod
    def url(self) -> str:
        raise NotImplementedError

    @abstractmethod
    def title(self) -> str:
        raise NotImplementedError

    def close(self) -> None:  # pragma: no cover - optional cleanup hook
        return None


class BrowserDriver(ABC):
    @abstractmethod
    def create_session(self) -> BrowserSession:
        raise NotImplementedError


class InMemoryBrowserSession(BrowserSession):
    def __init__(self) -> None:
        self.current_url = ""
        self.current_title = ""
        self.nodes: dict[str, str] = {}

    def open(self, url: str) -> Any:
        self.current_url = url
        return {"url": url}

    def click(self, selector: str) -> Any:
        return {"clicked": selector}

    def type(self, selector: str, text: str) -> Any:
        self.nodes[selector] = text
        return {"typed": selector}

    def text(self, selector: str) -> str:
        return self.nodes.get(selector, "")

    def url(self) -> str:
        return self.current_url

    def title(self) -> str:
        return self.current_title


class InMemoryBrowserDriver(BrowserDriver):
    def create_session(self) -> BrowserSession:
        return InMemoryBrowserSession()


class _PlaywrightSession(BrowserSession):
    def __init__(self, playwright, browser, context, page) -> None:
        self._playwright = playwright
        self._browser = browser
        self._context = context
        self._page = page

    def open(self, url: str) -> Any:
        self._page.goto(url)
        return {"url": self._page.url}

    def click(self, selector: str) -> Any:
        self._page.click(selector)
        return {"clicked": selector}

    def type(self, selector: str, text: str) -> Any:
        self._page.fill(selector, text)
        return {"typed": selector}

    def text(self, selector: str) -> str:
        return self._page.inner_text(selector)

    def url(self) -> str:
        return self._page.url

    def title(self) -> str:
        return self._page.title()

    def close(self) -> None:
        try:
            self._context.close()
        finally:
            try:
                self._browser.close()
            finally:
                self._playwright.stop()


class PlaywrightBrowserDriver(BrowserDriver):
    def __init__(self, *, headless: bool = True) -> None:
        self.headless = headless

    def create_session(self) -> BrowserSession:
        try:
            from playwright.sync_api import sync_playwright
        except Exception as e:  # noqa: BLE001
            raise RuntimeError(
                "playwright is required for PlaywrightBrowserDriver"
            ) from e
        playwright = sync_playwright().start()
        browser = playwright.chromium.launch(headless=self.headless)
        context = browser.new_context()
        page = context.new_page()
        return _PlaywrightSession(playwright, browser, context, page)


def browser_driver_from_name(name: str | None) -> BrowserDriver:
    key = (name or "memory").strip().lower()
    if key in {"memory", "in-memory", "fake"}:
        return InMemoryBrowserDriver()
    if key in {"playwright", "pw"}:
        return PlaywrightBrowserDriver()
    raise CantripError(f"unknown browser driver: {name}")
