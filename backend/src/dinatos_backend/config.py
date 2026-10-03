from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="DINATOS_", env_file=".env")

    database_url: str = "postgresql+asyncpg://dinatos:dinatos@localhost:5432/dinatos"

    # Sessions are revocable (see docs/architecture/backend.md's "Authentication"),
    # so unlike a stateless token's TTL, this doesn't have to be short to be
    # safe -- logout (or noticing a device was stolen) is the actual
    # mitigation. 30 days trades a little exposure window for not asking
    # someone logging their workouts to re-authenticate mid-week.
    session_ttl_days: int = 30

    # Needed whenever a Flutter *web* client is served from a different
    # origin than this backend -- e.g. `web_dir` below unset/missing and the
    # build served separately, or plain local dev (`flutter run -d
    # web-server`) -- without this the browser blocks every request with a
    # CORS error before it reaches the app at all. Not needed for the common
    # case of `web_dir` serving the bundled build itself (same origin, so
    # the browser never treats it as cross-origin to begin with), nor for
    # native targets (Android), which don't go through a browser either way.
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

    # Whether anyone can self-register from the login screen via `POST
    # /auth/register`. On by default (unchanged behavior for an existing
    # instance); set `DINATOS_ALLOW_REGISTRATION=false` for an invite-only
    # one, where an admin creates accounts instead (`POST /admin/users`).
    # Never locks out the very first account: with no users yet there is no
    # admin to create one, so registration stays open until it exists --
    # see `services.auth.is_registration_open`.
    allow_registration: bool = True

    # Seeds a standard catalog of common exercises into a brand new
    # instance's empty `exercises` table on startup -- see
    # `services.exercise.bootstrap_default_exercises`. On by default (an
    # empty exercise picker on first launch is worse than a starting list
    # to build workouts from immediately); those seeded rows are immutable
    # (`Exercise.is_custom`), so someone who doesn't want one just adds
    # their own custom exercise instead. `screenshots/generate.py` turns
    # this off so its own curated, demo-sized exercise list stays exactly
    # what it creates.
    seed_default_exercises: bool = True

    # Gives each brand new account a few classic starter routines (Push,
    # Pull, Legs, ...) built from that seeded catalog -- see
    # `services.starter_routines`. Skips any exercise missing from the
    # catalog, so it's a no-op when `seed_default_exercises` is off.
    seed_default_routines: bool = True

    # Where to look for a built Flutter web app (an `index.html` plus its
    # assets) to serve alongside the API -- see `main.py`. Relative to the
    # process's working directory, which is why the Docker image's runtime
    # stage copies the web build to exactly `web/` under its `/app` WORKDIR:
    # the default here needs no override to find it there. A directory that
    # doesn't exist (the common case outside the Docker image -- e.g. `just
    # backend run`, or these test suites) just means nothing is mounted and
    # the API behaves exactly as it did before this setting existed. Point
    # this at a different build (or set it to a nonexistent path to disable
    # serving one at all) without needing to rebuild the image.
    web_dir: str = "web"


@lru_cache
def get_settings() -> Settings:
    return Settings()
