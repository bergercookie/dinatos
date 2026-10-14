# Configuration reference

Every backend setting, as an environment variable. All have defaults. Only the database URL must point at a real Postgres, and `docker-compose.yml` already does that.

## Setting variables with Docker Compose

`docker-compose.yml` passes only these through from `.env` to the app container: `POSTGRES_*`, `DINATOS_ALLOW_REGISTRATION`, `DINATOS_ADMIN_EMAIL`, `DINATOS_ADMIN_PASSWORD`. To set any other variable below, add it under `services.backend.environment` in `docker-compose.yml`, then run `docker compose up -d`. Example:

```yaml
    environment:
      DINATOS_SESSION_TTL_DAYS: "14"
      DINATOS_CORS_ALLOWED_ORIGINS: '["https://app.example.com"]'
```

List values take JSON.

## Variables

| Variable | Default | Meaning |
|---|---|---|
| `DINATOS_DATABASE_URL` | `postgresql+asyncpg://dinatos:dinatos@localhost:5432/dinatos` | Postgres connection. Compose builds it from `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`. |
| `DINATOS_SESSION_TTL_DAYS` | `30` | Days a login lasts. Logging out revokes a session at once, so there is little reason to shorten it. |
| `DINATOS_ALLOW_REGISTRATION` | `true` | `false` hides Register and rejects self-registration. Administrators add users in **Settings -> Administration**. Registration stays open while no accounts exist, so the first admin can be created. |
| `DINATOS_ADMIN_EMAIL`, `DINATOS_ADMIN_PASSWORD` | unset | If both are set, creates this admin on startup if missing. Never changes an existing account. |
| `DINATOS_SEED_DEFAULT_EXERCISES` | `true` | On first start with an empty exercise list, adds a standard catalog of built-in exercises. |
| `DINATOS_SEED_DEFAULT_ROUTINES` | `true` | Gives each new account starter routines (Push, Pull, Legs, Upper body, Lower body, Full body). Each is the account's own copy. Needs the exercise catalog. |
| `DINATOS_CORS_ALLOWED_ORIGINS` | `["*"]` | Browser origins allowed to call the API. Needed only for a web build on a different origin. See [CORS](security-and-networking.md#cors). |
| `DINATOS_WEB_DIR` | `web` | Folder with the built web app, relative to the app's working directory. The Docker image already contains it. A missing folder only disables the web UI. The API is unaffected. |

## Env files

| File | Used by |
|---|---|
| `.env` at the repo root | `docker compose` |
| `backend/.env` | Running the backend directly, for development |

Copy `.env.example` (repo root) for Docker.
