import pytest

from dinatos_mcp import server
from dinatos_mcp.__main__ import main


def test_runs_the_server_over_stdio(monkeypatch: pytest.MonkeyPatch) -> None:
    called: dict[str, str] = {}
    monkeypatch.setattr(server.mcp, "run", lambda **kwargs: called.update(kwargs))

    main()

    assert called == {"transport": "stdio"}
