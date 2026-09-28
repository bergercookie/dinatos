# Getting started

The backend is a real FastAPI + Postgres API, with multi-user accounts,
exercises, workouts, activities, a profile, body measurements, and a Hevy
CSV importer. `frontend/` is a Flutter app against it -- see
`docs/architecture.md` for the build order and both pieces' structure.

```bash
just install   # create the backend virtualenv
just check     # lint, test, build docs -- what CI runs -- no database needed
```

`just` on its own lists every available recipe.

## Fastest path: `just dev`

```bash
cp .env.example .env   # then edit it -- POSTGRES_PASSWORD has no default,
                        # and set DINATOS_ADMIN_EMAIL/DINATOS_ADMIN_PASSWORD
                        # too, so there's an account to log in with
just dev
```

This starts Postgres (via Docker), runs migrations, and runs the backend
and the frontend together -- open the frontend URL it prints
(`http://127.0.0.1:8081`) and log in with whatever you set
`DINATOS_ADMIN_EMAIL`/`DINATOS_ADMIN_PASSWORD` to. Ctrl+C stops the backend
and frontend; Postgres itself keeps running. Use `just docker down` to stop
the Docker resources while keeping the database, or `just dev-clean` to
remove the backend and Postgres containers, their network, and the Postgres
data volume. Needs Docker and the Flutter SDK on `PATH` -- see AGENTS.md if
either isn't already set up.

The rest of this page covers running each piece separately (useful for,
e.g., hot-reloading just the frontend against a backend `just dev` already
started, or deploying only the backend).

## Running the API

Everything in "Fastest path" above needs a real Postgres; everything in
the first code block at the top of this page (`just check`) does not (the
test suite runs against an in-memory sqlite). Three ways to get a backend
running on its own:

**`just backend run`**, against Postgres from `just docker up` below (or
one you run yourself) -- picks up `backend/.env` if present (see
`backend/.env.example`; this is a *separate* file from the repo root's
`.env`, which only `docker compose`/`just dev` read).

**With Docker** (`backend/Dockerfile` + `docker-compose.yml` at the repo
root -- Postgres and the backend together, migrations run automatically on
container start, see `backend/docker-entrypoint.sh`):

```bash
cp .env.example .env   # then edit it -- POSTGRES_PASSWORD has no default
                        # and the containers refuse to start without it
just docker up      # http://127.0.0.1:8000 -- /docs for the interactive API
just docker logs    # follow the backend's logs
just docker down    # stop; the postgres data volume is kept
```

**Without Docker**, against a Postgres you run yourself:

```bash
docker run -d --name dinatos-pg -e POSTGRES_USER=dinatos -e POSTGRES_PASSWORD=dinatos \
    -e POSTGRES_DB=dinatos -p 5432:5432 postgres:16-alpine
cd backend
uv run alembic upgrade head
just run   # http://127.0.0.1:8000 -- /docs for the interactive API
```

## Creating an account

Every endpoint except `/health` and `/auth/*` needs a bearer token.
`DINATOS_ADMIN_EMAIL`/`DINATOS_ADMIN_PASSWORD` (see "Fastest path" above)
creates that account automatically, as admin, the first time the backend
starts -- the common case, and what avoids needing any of the below by
hand. It's a no-op on every later restart if the account already exists,
and never touches its password if you've since changed it.

Without those settings, the first account *registered* on a fresh instance
(from the app's own Register screen, or by hand) becomes its admin instead:

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

Sessions last 30 days (`session_ttl_days`) and there is no refresh -- once
one expires, `POST /auth/login` again. `POST /auth/logout` (no body,
same bearer header) ends a session early: a real server-side revocation of
exactly the token used to call it -- that token gets a `401` on every
request after, immediately, not just "discard it and hope". See
`docs/architecture.md`'s "Authentication" section for the full design and
why it changed from an earlier stateless-JWT version.

## Running the frontend

With the backend up (any way above), the Flutter app just needs to be
told where to reach it:

```bash
cd frontend
just install
just run   # flutter run -d web-server --web-port 8081, hot reload
```

Open `http://127.0.0.1:8081`. The **Server URL** field on the login screen
(prefilled with `http://127.0.0.1:8000`) is what points the app at a
backend -- edit it there (or later, from the profile screen) rather than
rebuilding; it's saved on the device/browser, not baked into the build. A
fixed default for a release build you distribute yourself is still
available via `--dart-define=API_BASE_URL=https://...`, but that's the
exception, not how you'd normally point a dev build at a different backend.

The first screen is register/login -- log in with the admin account above,
or register a new one from the app instead of curl if you'd rather not
construct the requests by hand. A session lasts 30 days (see
"Authentication"); the app doesn't paper over its end with a silent
refresh, since there is nothing to refresh -- once a request comes back
`401` (expired, or logged out from this device or another), it drops you
back to the login screen. The profile screen's app bar icon logs out for
real: it revokes the session server-side, not just the token stored in
this browser/device.

`just frontend check` (format check, `flutter analyze`, `flutter test`)
mirrors `just check` for the backend, but needs the Flutter SDK, not just
Python/uv -- see AGENTS.md for why it's a separate recipe and CI job rather
than folded into the root `just check`.

## Browsing the API documentation

Every endpoint is described by the schema FastAPI generates from the code, so
the docs can't drift from the API. Open it straight from the running backend:

- `http://127.0.0.1:8000/docs` -- Swagger UI, with a "Try it out" button
- `http://127.0.0.1:8000/redoc` -- ReDoc, a read-only reference
- `http://127.0.0.1:8000/openapi.json` -- the raw schema, for codegen

The app has the same page inlined, so you don't have to leave it: Profile ->
"API documentation". On the web target that embeds the backend's own Swagger UI
in a frame (the page itself lives at `/#/docs` -- Flutter web routes with a
hash, so that's the honest form of the URL). On a phone or desktop build, and
on the web when the browser won't allow the frame, that screen falls back to
the links above with a copy button.

Two things worth knowing:

- Everything except `/health` and the login/register endpoints needs
  `Authorization: Bearer $token`, so the docs page's "Try it out" needs a token
  too. `/auth/me` and `/auth/logout` are themselves authenticated.
- Swagger UI loads its JavaScript and CSS from a public CDN
  (`cdn.jsdelivr.net`). Behind an air gap, or offline, the page's frame and
  buttons won't render -- `/openapi.json` still will, and is the better input
  to codegen anyway.

## Importing your Hevy history

Export your data from Hevy (Settings -> Export), then upload both CSVs from
the app itself: Profile -> "Import from Hevy". This is a one-shot migration,
not a sync -- uploading the exact same file again asks you to confirm before
re-importing it, rather than silently creating duplicates.

Without the app (e.g. scripting a fresh instance's setup), the same two
endpoints work directly, authenticated as above:

```bash
curl -F file=@workout_data.csv http://127.0.0.1:8000/imports/hevy/workouts \
    -H "Authorization: Bearer $token"
curl -F file=@measurement_data.csv http://127.0.0.1:8000/imports/hevy/measurements \
    -H "Authorization: Bearer $token"
```

Uploading the exact same file again is rejected with `409 Conflict` rather
than creating duplicates; add `?force=true` to the URL if you really mean to
re-import it.
