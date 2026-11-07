from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="DINATOS_MCP_", env_file=".env")

    # Where your Dinatos server lives (the address you open in a browser).
    # Required: there is no sensible default, because a proxy that silently
    # talks to http://127.0.0.1:8000 fails confusingly when the server is
    # somewhere else. It is typed optional only so that a missing value
    # becomes a clear error at the first request (`RemoteTools._session`).
    base_url: str | None = None

    # An API key from Settings > API keys in the app. The only way to
    # authenticate: not your password, and not a login token.
    api_key: str | None = None

    @property
    def mcp_url(self) -> str:
        """The server's own MCP endpoint, which does all the work."""
        if not self.base_url:
            raise ValueError("base_url is not set (DINATOS_MCP_BASE_URL)")
        return self.base_url.rstrip("/") + "/mcp"


@lru_cache
def get_settings() -> Settings:
    return Settings()
