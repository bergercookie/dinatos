# Running and testing

## Fastest path: `just dev`

```bash
cp .env.example .env   # then edit it -- POSTGRES_PASSWORD has no default,
                        # and set DINATOS_ADMIN_EMAIL/DINATOS_ADMIN_PASSWORD
                        # too, so there's an account to log in with
just dev
```

This starts Postgres (via Docker), runs migrations, and runs the backend and
the frontend together -- open the frontend URL it prints
(`http://127.0.0.1:8081`) and log in with whatever you set
`DINATOS_ADMIN_EMAIL`/`DINATOS_ADMIN_PASSWORD` to. Ctrl+C stops the backend
and frontend; Postgres itself keeps running. Use `just docker down` to stop
the Docker resources while keeping the database, or `just dev-clean` to
remove the backend and Postgres containers, their network, and the Postgres
data volume -- that last one is destructive, see
[Upgrades and backups](../deploy/upgrades-and-backups.md) before reaching
for it against data you care about.

The rest of this page covers running each piece separately -- useful for,
e.g., hot-reloading just the frontend against a backend `just dev` already
started.

## Running the API on its own

Three ways, in increasing order of how much you're standing up yourself:

**`just backend run`**, against Postgres from `just docker up` (see
[Deploying with Docker Compose](../deploy/quickstart.md)) or one you run
yourself -- picks up `backend/.env` if present.

**With Docker** (the root `Dockerfile` + `docker-compose.yml` at the repo
root -- Postgres and the app together, migrations run automatically on
container start). Note this builds the bundled web app too (the
`frontend-builder` stage needs the Flutter SDK, which this downloads itself
-- see the `Dockerfile`'s own comments), so it's slower than `just backend
run` above for a backend-only edit/test loop:

```bash
cp .env.example .env   # then edit it
just docker up      # http://127.0.0.1:8000 -- the app itself; /docs for the API
just docker logs     # follow its logs
just docker down     # stop; the postgres data volume is kept
```

**Without Docker**, against a Postgres you run yourself:

```bash
docker run -d --name dinatos-pg -e POSTGRES_USER=dinatos -e POSTGRES_PASSWORD=dinatos \
    -e POSTGRES_DB=dinatos -p 5432:5432 postgres:16-alpine
cd backend && uv run alembic upgrade head
just run   # http://127.0.0.1:8000 -- /docs for the interactive API
```

### Creating an account for testing

`DINATOS_ADMIN_EMAIL`/`DINATOS_ADMIN_PASSWORD` (see "Fastest path" above)
creates that account automatically, as admin, on first startup -- the usual
path, and what avoids needing any of the below by hand.

Without those settings, the first account *registered* on a fresh instance
becomes its admin instead:

```bash
curl -X POST http://127.0.0.1:8000/auth/register \
    -H "Content-Type: application/json" \
    -d '{"email": "you@example.com", "password": "at-least-8-characters"}'

token=$(curl -X POST http://127.0.0.1:8000/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email": "you@example.com", "password": "at-least-8-characters"}' \
    | jq -r .access_token)

curl http://127.0.0.1:8000/exercises -H "Authorization: Bearer $token"
```

See [Authentication](../architecture/backend.md#authentication) for how
sessions and logout actually work.

## Running the frontend on its own

```bash
cd frontend
just install
just run   # flutter run -d web-server --web-port 8081, hot reload
```

Open `http://127.0.0.1:8081`. The **Server URL** field on the login screen
(prefilled with `http://127.0.0.1:8000`) points the app at a backend --
useful for pointing a hot-reloading frontend at a `just dev` backend already
running, or at any other instance. See
[Getting started](../user-guide/getting-started.md) for what this field
means from an end user's side.

`just frontend check` (format check, `flutter analyze`, `flutter test`)
mirrors `just check` for the backend, but needs the Flutter SDK -- see
[Environment setup](environment-setup.md) and
[CI and releases](ci-and-releases.md) for why it's a separate recipe and CI
job rather than folded into the root `just check`.

## Coverage requires `concurrency = ["greenlet"]`

SQLAlchemy's async engine bridges every DBAPI call through `greenlet`.
Without `concurrency = ["greenlet"]` in `[tool.coverage.run]`
(`backend/pyproject.toml`), coverage.py silently stops tracking a function's
lines *after* its first `await db.something(...)` -- not just
under-reporting a little, entire tail ends of correct, tested router
functions show up as 0% covered. If a fresh `just backend test` ever reports
a big unexplained coverage drop right after touching DB code, check this
setting is still there before assuming the code regressed.

## Testing migrations

`just backend test-migrations` (`backend/tests_migrations/`) runs
[pytest-alembic](https://pytest-alembic.readthedocs.io/)'s built-in suite
against a real, throwaway Postgres spun up by `testcontainers`: a single
head revision, a clean base->head upgrade, the models matching the DDL the
migrations produce, and -- the one that matters most --
`test_up_down_consistency`, which upgrades and downgrades *every* migration
individually, not just head<->base. That last one is how a real
Postgres-specific bug (an ENUM type left behind by a `downgrade()`, breaking
the next `upgrade()`) was actually caught -- a sqlite-backed test would never
have caught it, since sqlite has no `CREATE TYPE` to forget to undo in the
first place.

It needs Docker and takes real seconds, so it's not part of `just check` --
CI runs it as its own `migrations` job instead (see
[CI and releases](ci-and-releases.md)).

Alembic's own config lives in `backend/pyproject.toml`'s `[tool.alembic]`,
not `alembic.ini` (which now holds only the `[loggers]`/`[handlers]`/
`[formatters]` sections `env.py`'s `logging.config.fileConfig()` call
needs -- that stdlib function only understands the ini format). Don't add
anything back to `alembic.ini`'s `[alembic]` section: a key set in *both*
places has the ini value win silently, defeating the point of having moved
it.
