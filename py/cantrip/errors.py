class CantripError(Exception):
    """Domain error for cantrip runtime."""


class ProviderError(CantripError):
    """HTTP error from an LLM provider."""

    def __init__(self, status_code: int | None, message: str) -> None:
        self.status_code = status_code
        self.message = message
        super().__init__(f"provider_error:{status_code}:{message}")


class ProviderTimeout(CantripError):
    """Timeout contacting an LLM provider."""

    def __init__(self, message: str) -> None:
        self.message = message
        super().__init__(f"provider_timeout:{message}")


class ProviderTransportError(CantripError):
    """Transport-level error contacting an LLM provider."""

    def __init__(self, message: str) -> None:
        self.message = message
        super().__init__(f"provider_transport_error:{message}")
