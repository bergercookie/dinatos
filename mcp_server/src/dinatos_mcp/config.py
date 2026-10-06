from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="DINATOS_MCP_", env_file=".env")

    # Where your Dinatos server lives (the address you open in a browser).
    base_url: str = "http://127.0.0.1:8000"

    # An API key from Settings > API keys in the app. The only way to
    # authenticate: not your password, and not a login token.
    api_key: str | None = None

    @property
    def mcp_url(self) -> str:
        """The server's own MCP endpoint, which does all the work."""
        return self.base_url.rstrip("/") + "/mcp"


@lru_cache
def get_settings() -> Settings:
    return Settings()
