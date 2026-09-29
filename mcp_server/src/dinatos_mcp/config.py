from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="DINATOS_MCP_", env_file=".env")

    # Where the Dinatos backend itself lives -- the default matches
    # `just backend run`/`just dev`'s own default port.
    base_url: str = "http://127.0.0.1:8000"

    # Either set this directly (a token from `POST /auth/login`, e.g. via
    # the curl recipe in docs/development/workflow.md), or set both `email`
    # and `password` below and `DinatosClient` logs in for you on first use.
    # A token set here wins if both are present.
    token: str | None = None

    email: str | None = None
    password: str | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()
