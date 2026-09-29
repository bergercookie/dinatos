import pytest

from dinatos_mcp.config import Settings, get_settings


@pytest.fixture(autouse=True)
def _clear_settings_cache() -> None:
    get_settings.cache_clear()


def test_defaults_need_no_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    for name in ("DINATOS_MCP_BASE_URL", "DINATOS_MCP_TOKEN", "DINATOS_MCP_EMAIL"):
        monkeypatch.delenv(name, raising=False)

    settings = Settings()

    assert settings.base_url == "http://127.0.0.1:8000"
    assert settings.token is None
    assert settings.email is None
    assert settings.password is None


def test_reads_overrides_from_the_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DINATOS_MCP_BASE_URL", "http://dinatos.example.com")
    monkeypatch.setenv("DINATOS_MCP_TOKEN", "a-session-token")

    settings = Settings()

    assert settings.base_url == "http://dinatos.example.com"
    assert settings.token == "a-session-token"


def test_get_settings_is_cached() -> None:
    assert get_settings() is get_settings()
