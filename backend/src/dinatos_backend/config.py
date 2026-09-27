from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="DINATOS_", env_file=".env")

    database_url: str = "postgresql+asyncpg://dinatos:dinatos@localhost:5432/dinatos"

    # Sessions are revocable (see docs/architecture.md's "Authentication"),
    # so unlike a stateless token's TTL, this doesn't have to be short to be
    # safe -- logout (or noticing a device was stolen) is the actual
    # mitigation. 30 days trades a little exposure window for not asking
    # someone logging their workouts to re-authenticate mid-week.
    session_ttl_days: int = 30

    # The Flutter *web* target is served from its own origin (a different
    # port at minimum), so without this the browser blocks every request
    # with a CORS error before it reaches the app at all -- native targets
    # (Android) don't go through a browser and aren't affected either way.
    # `["*"]` is safe here specifically because auth is a bearer token in a
    # header, never a cookie: there's no session for a third-party site to
    # ride along on (`allow_credentials` stays False), which is the actual
    # risk a wildcard origin creates. Override for a locked-down deployment.
    cors_allowed_origins: list[str] = ["*"]

    # Optional: if both are set, the app creates this account (as admin) on
    # startup if it doesn't already exist -- see
    # `services.auth.bootstrap_admin_user`. Lets a fresh instance's first
    # login work without a manual `curl -X POST /auth/register` first.
    # Neither has a default: unset (the common case for an existing
    # instance) means bootstrap does nothing at all.
    admin_email: str | None = None
    admin_password: str | None = None

    # Seeds a standard catalog of common exercises into a brand new
    # instance's empty `exercises` table on startup -- see
    # `services.exercise.bootstrap_default_exercises`. On by default (an
    # empty exercise picker on first launch is worse than a starting list
    # someone can edit or delete from); `screenshots/generate.py` turns
    # this off so its own curated, demo-sized exercise list stays exactly
    # what it creates.
    seed_default_exercises: bool = True

    # Opts into WorkoutX (https://workoutxapp.com) for exercise tutorials
    # (real animated GIFs, richer per-exercise metadata) instead of the
    # bundled free-exercise-db dataset -- see
    # `services.tutorials.get_tutorial_provider`. A homelab admin brings
    # their own WorkoutX account and API key; unset (the default) means
    # the bundled dataset is used, which needs no signup and no network
    # access. WorkoutX's own terms forbid bulk-caching their data, so this
    # is fetched and cached one exercise at a time, in memory only, never
    # written to the database -- see `services.tutorials.cache`.
    workoutx_api_key: str | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()
