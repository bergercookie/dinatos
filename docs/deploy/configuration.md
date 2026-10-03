# Configuration reference

Every setting the backend reads, as environment variables prefixed
`DINATOS_` (source of truth: `backend/src/dinatos_backend/config.py`).
Every one of them has a default -- nothing is required beyond
`DINATOS_DATABASE_URL` pointing at a real Postgres, and `docker-compose.yml`
already sets that for you if you're using it.

| Variable | Default | What it does |
|---|---|---|
| `DINATOS_DATABASE_URL` | `postgresql+asyncpg://dinatos:dinatos@localhost:5432/dinatos` | Where the backend connects. `docker-compose.yml` builds this from `POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB` automatically. |
| `DINATOS_SESSION_TTL_DAYS` | `30` | How long a login session lasts before it must be renewed by logging in again. Sessions are individually revocable (see [Authentication](../architecture/backend.md#authentication)), so this is a backstop for a session nobody ever explicitly ends, not the only thing standing between a leaked token and account compromise -- there's no strong security reason to shorten it. |
| `DINATOS_CORS_ALLOWED_ORIGINS` | `["*"]` | Which origins a browser is allowed to call the API from. Not needed for the bundled web UI (`DINATOS_WEB_DIR` below), which is always same-origin -- only for a Flutter *web* build served from a different origin than the backend (see [Clients](clients.md)). Safe as a wildcard specifically because auth is a bearer token in a header, never a cookie (there's no ambient session for a third-party site to ride along on). Override with a JSON list of specific origins for a locked-down deployment. |
| `DINATOS_WEB_DIR` | `web` | Where to find a built Flutter web app (an `index.html` plus its assets) to serve alongside the API, resolved relative to the backend's working directory. The Docker image's `web/` (baked in by its `frontend-builder` build stage) is exactly this default, so there's nothing to set for the common case -- see [Clients](clients.md). A path that doesn't exist (true outside the Docker image, e.g. `just backend run`) just means nothing is served there; the API itself is unaffected either way. |
| `DINATOS_ADMIN_EMAIL` / `DINATOS_ADMIN_PASSWORD` | unset | If **both** are set, creates this account (as admin) on startup if it doesn't already exist yet. Unset (the common case for an already-running instance) means this does nothing at all -- it never touches an existing account's password. See [Quickstart](quickstart.md). |
| `DINATOS_ALLOW_REGISTRATION` | `true` | Whether the login screen's "Register" link / `POST /auth/register` accept new accounts. Set to `false` for an invite-only instance: admins (the first account created, or `DINATOS_ADMIN_EMAIL`) then add accounts from **Profile → Administration** in the app, or `POST /admin/users`. An instance with no accounts yet always allows registration, so the first admin can still be created. |
| `DINATOS_SEED_DEFAULT_EXERCISES` | `true` | Seeds a standard catalog of common exercises into a brand-new instance's empty exercise list on first startup. An empty exercise picker on first launch is worse than a starting list you can edit or delete from; turn it off if you'd rather start with nothing. |
| `DINATOS_SEED_DEFAULT_ROUTINES` | `true` | Gives every new account a few classic starter routines (Push, Pull, Legs, Upper body, Lower body, Full body) built from the seeded exercise catalog, so nobody starts from a blank slate. Each is the account's own copy to edit or delete. Does nothing if the exercise catalog is off. |

Copy `.env.example` (repo root, read by `docker compose`/`just dev`) or
`backend/.env.example` (read by the backend directly, e.g.
`just backend run`) to get started -- these are two separate files for two
different ways of running the backend, see
[Environment setup](../development/environment-setup.md#env-files) if
you're not sure which one applies to you.
