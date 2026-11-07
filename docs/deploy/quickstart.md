# Quickstart

This page shows how to start a Dinatos instance with Docker Compose. Compose runs two containers: Postgres and the app container.

You need Docker with the Compose plugin, and Git.

## 1. Start the instance

1. Get the code and make your `.env` file:

   ```bash
   git clone https://github.com/bergercookie/dinatos.git
   cd dinatos
   cp .env.example .env
   ```

2. Edit `.env`. See [Set `.env`](#3-set-env) for the variables.
3. Start the containers:

   ```bash
   docker compose up -d
   ```

The first start builds the image from source. This takes a few minutes. Database migrations run automatically on every start.

The command `just docker up` does the same as `docker compose up -d`.

## 2. Open the web app

1. Open `http://127.0.0.1:8000` in a browser. This is the web app.
2. To check the health of the instance, run `curl http://127.0.0.1:8000/health`.

The app container listens on localhost only. To make it reachable from other machines, see [Security and networking](security-and-networking.md).

## 3. Set `.env`

| Variable | Required | Meaning |
|---|---|---|
| `POSTGRES_PASSWORD` | Yes | Password of the database. The containers do not start without it. |
| `POSTGRES_USER`, `POSTGRES_DB` | No | Both default to `dinatos`. |
| `DINATOS_UID`, `DINATOS_GID` | No | Owner of the Postgres data directory. Both default to `1000`. Set them to the output of `id -u` and `id -g`. |
| `DINATOS_DATA_DIR` | No | Folder on the host for the data. The default is `./data`. |
| `DINATOS_ADMIN_EMAIL`, `DINATOS_ADMIN_PASSWORD` | No | Set both to make this administrator account on the first start. Dinatos never changes the password of an existing account. |
| `DINATOS_ALLOW_REGISTRATION` | No | `false` stops self-registration. The default is `true`. |

If you do not set the administrator variables, the first account that registers becomes the administrator. Administrators add users in **Settings -> Administration**.

All other settings are in the [Configuration reference](configuration.md).

## Day-to-day commands

| Task | Command |
|---|---|
| Follow the logs | `docker compose logs -f backend` |
| Stop the containers (Dinatos keeps the data) | `docker compose down` |
| Upgrade | See [Upgrades and backups](upgrades-and-backups.md) |

## API documentation

The running server shows its own API documentation:

| URL | Content |
|---|---|
| `/docs` | Swagger UI with "Try it out". It needs a login token. |
| `/redoc` | Read-only reference |
| `/openapi.json` | Raw schema |

Swagger UI loads scripts from `cdn.jsdelivr.net`. Without internet access, the Swagger UI page does not show. `/openapi.json` still works.

## Next

To connect a client, see [Clients](clients.md).
