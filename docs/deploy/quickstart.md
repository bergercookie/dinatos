# Quickstart

Start a Dinatos instance with Docker Compose. Compose runs two containers: Postgres, and the app (the API plus the web UI, served together).

You need Docker with the Compose plugin, and Git.

## 1. Start it

```bash
git clone https://github.com/bergercookie/dinatos.git
cd dinatos
cp .env.example .env
```

Edit `.env`, then:

```bash
docker compose up -d
```

The first run builds the image from source, which takes a few minutes. Database migrations run automatically on every start.

(`just docker up` does the same.)

## 2. Open it

Go to `http://127.0.0.1:8000`. That is the web app. The container listens on localhost only. See [Security and networking](security-and-networking.md) to expose it.

Check health with `curl http://127.0.0.1:8000/health`.

## 3. Set `.env`

| Variable | Required | Meaning |
|---|---|---|
| `POSTGRES_PASSWORD` | Yes | Database password. The containers refuse to start without it. |
| `POSTGRES_USER`, `POSTGRES_DB` | No | Both default to `dinatos`. |
| `DINATOS_ADMIN_EMAIL`, `DINATOS_ADMIN_PASSWORD` | No | Set both to create this admin account on first start. An existing account's password is never changed. |
| `DINATOS_ALLOW_REGISTRATION` | No | `false` stops self-registration. Default `true`. |

Without the admin variables, the first account registered becomes the administrator. Administrators add users under **Settings -> Administration**.

Every other setting is in the [Configuration reference](configuration.md).

## Day-to-day commands

| Task | Command |
|---|---|
| Follow logs | `docker compose logs -f backend` |
| Stop (data is kept) | `docker compose down` |
| Upgrade | See [Upgrades and backups](upgrades-and-backups.md) |

## API documentation

The running server documents its own API:

| URL | Content |
|---|---|
| `/docs` | Swagger UI with "Try it out". Needs a login token. |
| `/redoc` | Read-only reference |
| `/openapi.json` | Raw schema |

Swagger UI loads scripts from `cdn.jsdelivr.net`. Without internet access its page does not render. `/openapi.json` still works.

## Next

Connect a client: see [Clients](clients.md).
