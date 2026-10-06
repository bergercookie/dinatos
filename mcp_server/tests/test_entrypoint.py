from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import pytest

from dinatos_mcp import __main__ as entrypoint


def test_serves_over_stdio(monkeypatch: pytest.MonkeyPatch) -> None:
    ran: list[tuple[object, object]] = []

    class FakeServer:
        def create_initialization_options(self) -> str:
            return "options"

        async def run(self, read: object, write: object, options: object) -> None:
            ran.append((read, write))
            assert options == "options"

    @asynccontextmanager
    async def fake_stdio() -> AsyncIterator[tuple[str, str]]:
        yield ("read", "write")

    monkeypatch.setattr(entrypoint, "build_server", FakeServer)
    monkeypatch.setattr(entrypoint, "stdio_server", fake_stdio)

    entrypoint.main()

    assert ran == [("read", "write")]
