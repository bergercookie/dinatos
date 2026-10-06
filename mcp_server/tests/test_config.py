import pytest

from dinatos_mcp.config import Settings, get_settings


def test_defaults_need_no_environment() -> None:
    settings = Settings()

    assert settings.base_url == "http://127.0.0.1:8000"
    assert settings.api_key is None
    assert settings.mcp_url == "http://127.0.0.1:8000/mcp"


def test_reads_overrides_from_the_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DINATOS_MCP_BASE_URL", "https://dinatos.example.com/")
    monkeypatch.setenv("DINATOS_MCP_API_KEY", "dnk_abc")

    settings = Settings()

    assert settings.mcp_url == "https://dinatos.example.com/mcp"
    assert settings.api_key == "dnk_abc"


def test_passwords_and_login_tokens_are_not_settings() -> None:
    assert not {"token", "email", "password"} & set(Settings.model_fields)


def test_get_settings_is_cached() -> None:
    assert get_settings() is get_settings()
