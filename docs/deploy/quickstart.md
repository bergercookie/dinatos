# Quickstart

Dinatos ships as one Docker image (the backend API plus the built web app,
served together) plus Postgres; `docker-compose.yml` at the repo root wires
the two together. This is the fastest path to a running instance -- see
[Clients](clients.md) right after for other ways to connect to it (native
Android/Linux clients, or a web build served from its own origin).

```bash
git clone https://github.com/bergercookie/dinatos.git
cd dinatos
cp .env.example .env   # then edit it -- see below for what to set
docker compose up -d
```

(Or, with `just` on `PATH`: `just docker up` -- an identical wrapper around
the same `docker compose` invocation.)

This starts Postgres and the app, and runs database migrations
automatically on the app's first start -- nothing extra to run by hand.
It listens on `http://127.0.0.1:8000` -- open that in a browser and you're
at the app itself (`/docs` for the interactive API instead); see
[Security and networking](security-and-networking.md) for why that's
`127.0.0.1`, not `0.0.0.0`, by design.

## `.env` -- what to set

```bash
# Required -- the containers refuse to start without it.
POSTGRES_PASSWORD=change-me

# Optional but recommended: creates this account, as admin, on the
# backend's first startup, so there's something to log in with without
# constructing a registration request by hand. Never touches an existing
# user's password on later restarts.
DINATOS_ADMIN_EMAIL=you@example.com
DINATOS_ADMIN_PASSWORD=change-me
```

Without `DINATOS_ADMIN_EMAIL`/`DINATOS_ADMIN_PASSWORD` set, the first
account anyone registers (from a client app's Register screen, or
`POST /auth/register` directly) becomes the instance's admin instead.
Admins can create further accounts from **Profile → Administration**. To
stop anyone else self-registering, set `DINATOS_ALLOW_REGISTRATION=false`.

See [Configuration reference](configuration.md) for every other setting.

## Operating it

```bash
docker compose logs -f backend   # follow the backend's logs
docker compose down               # stop; the postgres data volume is kept
```

(`just docker logs`/`just docker down` if you're using `just`.) See
[Upgrades and backups](upgrades-and-backups.md) before running anything
that touches the data volume itself.

## Browsing the API documentation

Every endpoint is described by the schema FastAPI generates from the code,
so it can't drift from what's actually deployed. Open it straight from the
running backend:

- `http://127.0.0.1:8000/docs` -- Swagger UI, with a "Try it out" button
- `http://127.0.0.1:8000/redoc` -- ReDoc, a read-only reference
- `http://127.0.0.1:8000/openapi.json` -- the raw schema, for codegen

(Substitute your own host/port if you're not on the machine running it.)
Every client app has the same page inlined too -- Profile -> "API
documentation" -- so whoever's using your instance doesn't need this URL at
all; see [Using the app](../user-guide/using-the-app.md#profile).

Two things worth knowing if your instance has no outbound internet access:

- "Try it out" needs a bearer token the same as any other client -- see
  [Authentication](../architecture/backend.md#authentication).
- Swagger UI loads its JavaScript and CSS from a public CDN
  (`cdn.jsdelivr.net`). Behind an air gap, the `/docs`/`/#/docs` page's frame
  and buttons won't render -- `/openapi.json` still will, and is the better
  input to codegen anyway. See
  [API documentation](../architecture/backend.md#api-documentation) for why.
