# Configuration reference

This page lists every backend setting as an environment variable. Each variable has a default. The database URL must point to a real Postgres. `docker-compose.yml` already does this.

## Setting variables with Docker Compose

`docker-compose.yml` passes only these variables from `.env` to the app container:

- `POSTGRES_*`
- `DINATOS_ALLOW_REGISTRATION`
- `DINATOS_MCP_ENABLED`
- `DINATOS_ADMIN_EMAIL`
- `DINATOS_ADMIN_PASSWORD`

To set any other variable from the table below, do these steps:

1. Add the variable under `services.backend.environment` in `docker-compose.yml`.
2. Run `docker compose up -d`.

Example:

```yaml
    environment:
      DINATOS_SESSION_TTL_DAYS: "14"
      DINATOS_CORS_ALLOWED_ORIGINS: '["https://app.example.com"]'
```

A list value must be JSON.

## Variables

| Variable | Default | Meaning |
|---|---|---|
| `DINATOS_DATABASE_URL` | `postgresql+asyncpg://dinatos:dinatos@localhost:5432/dinatos` | Postgres connection. Compose builds it from `POSTGRES_USER`, `POSTGRES_PASSWORD` and `POSTGRES_DB`. |
| `DINATOS_SESSION_TTL_DAYS` | `30` | Number of days a login lasts. A logout ends a session at once, so there is little reason to use a shorter time. |
| `DINATOS_ALLOW_REGISTRATION` | `true` | `false` hides Register and rejects self-registration. Administrators add users in **Settings -> Administration**. While no accounts exist, registration stays open. This lets you make the first administrator. |
| `DINATOS_MCP_ENABLED` | `true` | `false` turns off the built-in [MCP server](../user-guide/mcp-server.md). `/mcp` then answers 404 and Dinatos does not start the MCP server. API keys still work for everything else. The change takes effect after a restart. |
| `DINATOS_ADMIN_EMAIL`, `DINATOS_ADMIN_PASSWORD` | unset | If you set both, Dinatos makes this administrator account on startup when it does not exist. Dinatos never changes an existing account. |
| `DINATOS_SEED_DEFAULT_EXERCISES` | `true` | On the first start with an empty exercise list, Dinatos adds a standard catalog of built-in exercises. |
| `DINATOS_SEED_DEFAULT_ROUTINES` | `true` | Dinatos gives each new account these starter routines: Push, Pull, Legs, Upper body, Lower body and Full body. Each routine is a copy that belongs to the account. This setting needs the exercise catalog. |
| `DINATOS_CORS_ALLOWED_ORIGINS` | `["*"]` | Browser origins that can call the API. You need it only for a web app on a different origin. See [CORS](security-and-networking.md#cors). |
| `DINATOS_WEB_DIR` | `web` | Folder of the built web app. The path is relative to the working directory of the app. The Docker image already contains this folder. If the folder does not exist, only the web app is off. The API still works. |

## `.env` files

| File | Used by |
|---|---|
| `.env` at the repo root | `docker compose` |
| `backend/.env` | The backend, when you run it directly for development |

For Docker, copy `.env.example` from the repo root.
