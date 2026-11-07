# Backend

This page explains the design decisions of the API in `backend/`. It is for
contributors. Read the [domain model](domain-model.md) first for the terms.
The live endpoint reference is the server's own `/docs` page (see
[API documentation](#api-documentation)).

The server uses FastAPI, async SQLAlchemy, pydantic and Postgres. The code is
in `backend/src/dinatos_backend/`: `models/`, `schemas/`, `services/` and
`api/routers/`.

## API surface

`GET /health`, `/auth/*` and the calendar feed need no token. Every other
endpoint needs `Authorization: Bearer <token>`, where the token is a login
session or an [API key](#api-keys), and it shows only the data of the caller.

- **One catalog, private history.** All users share one exercise
  catalog. Records (`/exercises/{id}/records`) and history
  (`/exercises/{id}/history`) are for the caller only. A built-in exercise
  (`is_custom=False`) answers 403 to a change or delete.
- **Whole objects, not single sets.** `POST` and `PUT` on routines and
  activities create or replace the nested exercises and sets as a whole. No
  endpoint changes one set.
- **Another user's routine is a 404.** An activity can refer only to a
  routine of the caller. A reference to someone else's routine gets the same
  404 as a direct read.
- **A plan is not an activity**, because activities feed the statistics.
  `POST /activities` with `planned_workout_id` marks the plan as done. An
  unknown id does not make the save fail.
- **Supersets** (`superset_group`): the client keeps them consistent. See
  [Frontend](frontend.md#supersets).

### Retried saves

On an unreliable connection, a client cannot know if the server lost a request or only its response. The client then sends the request again. `POST /activities` treats a
request with the same caller, title, start time and end time as a replay: it
returns the existing activity with `200` instead of `201`.

The server needs no idempotency key: the start time of a live workout is a device
timestamp with full precision. Because the title is part of the key, the app
freezes the title once an attempt can have succeeded. See
[Frontend](frontend.md#saving-offline).

## API documentation

FastAPI serves `/docs` (Swagger UI), `/redoc` and `/openapi.json` from the
routers and schemas, so the reference cannot drift from the code. The app
embeds `/docs` in an iframe on web, and shows the URLs elsewhere.

- The app opens that screen with `context.go`, not `push`: with `push` the
  address bar keeps `#/profile`, which only shows up in a real browser.
- The app's own route is `/#/docs` (hash routing). Plain `/docs` is the
  backend's page.
- Swagger UI loads its assets from `cdn.jsdelivr.net`. Without internet
  access the frame is empty (`SwaggerUIBundle is not defined`), but
  `/openapi.json` still works.

## Authentication

Anyone can `POST /auth/register` unless registration is off. The first account
on a new instance becomes the admin, and it can always register, so an
instance can start with registration off. Admins create accounts with
`POST /admin/users`; `require_admin` protects `/admin/*`.

Registration and the [MCP server](#mcp-server) are server switches
(`services/instance_settings.py`):

- If the environment variable (`DINATOS_ALLOW_REGISTRATION`,
  `DINATOS_MCP_ENABLED`) has a value, it wins. "Set" comes from
  `Settings.model_fields_set`, because a default of `true` cannot tell
  "unset" from "set to true". An empty value counts as unset
  (`env_ignore_empty`), so Compose can pass it through unset.
- Otherwise an admin decides with `GET`/`PATCH /admin/settings`. The choice
  is a column of the one-row `instance_settings` table (`NULL` means "on"),
  which is in the backup.
- The variable locks its switch: `PATCH` returns `409` and changes nothing, also
  for the other switch in the same request. The app shows it disabled, and
  the server logs a warning at startup.

`GET /auth/config` is public. The login screen reads it to show or hide
"Register", and the MCP gateway reads it to know if `/mcp` is on.

### Sessions

Each login creates an `AuthSession` row. The token is random
(`generate_session_token`), and the server stores only its SHA-256 hash.

The server does not use a signed JWT, for two reasons:

- The server cannot revoke a stateless token before it expires, so
  `POST /auth/logout` could do nothing real.
- The server loads the `User` row on every request anyway, so a deleted
  account stops working at once. A signed token would not save that read.

Do not add JWT code (`pyjwt`, a signing-key setting) without these two
reasons in mind.

- Logout revokes only the session that its token names.
- Revoked, expired and unknown sessions all give the same `401`.
- The server checks expiry in SQL (`expires_at > func.now()`) to avoid timezone
  mismatches between the driver and Python.
- The default lifetime is 30 days (`session_ttl_days`). It is long because
  revocation is the real protection, and nobody wants a forced login in the
  middle of a workout.

### Password and token hashing

| Secret | Hash | Why |
| --- | --- | --- |
| Password | Argon2 (`argon2-cffi`) | Low entropy: a fast hash lets a thief of `users.password_hash` brute-force it. Argon2 is slow on purpose. |
| Session token, API key | SHA-256 | 256 random bits already. Argon2 would only slow down every request. |

## API keys

Users create named keys (`POST /api-keys`, Settings -> API keys) so that a
tool, mainly the [MCP server](#mcp-server), can act as them.

- A key is `dnk_` plus 32 random bytes. The server stores only its SHA-256 hash, and shows the key once.
- The server updates `last_used_at` at most once a minute, so using a key is not a
  write on every request. An account can have 25 keys.
- `get_current_user` accepts a key or a session. `get_session_user` accepts
  only a session; it protects key management, logout and `/admin/*`, so a
  leaked key cannot create more keys, hide itself or restore the server.

## Backup and data export

Two features share one envelope: a JSON document with `format`,
`format_version`, `exported_at` and `app_version` (`schemas/backup.py`).
Otherwise they differ.

### Full server backup (admin only)

`GET /admin/backup` exports every table; `POST /admin/backup/restore`
(multipart `file` plus `confirm=true`) resets the server to it
(`services/backup.py`).

- **Generic over the table metadata.** Every column of every table in
  `BACKED_UP_TABLES` goes out with its primary key. A new column needs no change. Add a new table to the list, or to `EXCLUDED_TABLES` with a
  reason; `test_backup_coverage.py` enforces this. Raise `FORMAT_VERSION`
  only when an old reader could not understand the change.
- **Validate, then replace.** `parse_backup` checks the whole document first:
  format, tables, columns and types, unique keys, foreign keys, and at least
  one admin. All problems come back at once as `422`. `restore_backup` then
  empties and refills every table in one transaction.
- **Postgres sequences.** Explicit ids leave serial sequences behind, so
  `reset_sequences` runs `setval(...)` after a restore (Postgres only).
- **Sessions are never backed up.** After a restore every login ends, except
  the restoring admin's, and only if the backup has a user with the same id
  *and* email (`session_kept` says which).

> [!WARNING]
> The backup contains password hashes and stored WorkoutX API keys in clear
> text, because a restore must produce a working server. Treat the file as a
> credential.

### A user's own data (`/profile/export`, `/profile/import`)

`services/user_export.py` writes a hand-made document (`UserExport`) with no
database ids: profile settings, the exercises the data uses, routines,
activities and measurements. It never has the password hash, sessions,
import records, the calendar token or the WorkoutX key.

- **Exercises travel by name.** An import reuses an existing exercise with
  the same name, unchanged, and creates a custom one otherwise.
- **Merge** (default) skips what already exists (a routine with the same
  name, an activity with the same title and start, a measurement with the
  same timestamp), so importing a file twice is harmless. **Replace**
  (`?mode=replace`) first deletes the caller's routines, activities and
  measurements.
- **`DELETE /profile/data`** removes the caller's data and every custom
  exercise that no routine or activity of *any* user still uses.
- The server validates the whole file before the first write, and applies it in one transaction. Every written row gets the caller as `owner_id`.

### When you add a table or column

1. A new table goes in `BACKED_UP_TABLES` (the coverage test forces this).
2. A field that belongs to a user also goes in the `Exported*` models in
   `schemas/backup.py` and in `services/user_export.py`. No test can tell if a
   column belongs in a user's export: this step is on you.
3. Add a value for it to `tests/backup_seed.py`, which the round-trip tests
   compare in full.

## Calendar feed

`GET /calendar/{token}.ics` serves the caller's planned workouts as iCalendar
(`services/calendar.py`), so calendar apps can subscribe. Calendar apps cannot
log in, so the random token in the path (`secrets.token_urlsafe(32)`) is the
credential.

- The server stores the token in clear text so the app can show the link again. For
  the same reason it is not in the per-user export.
- `POST /profile/calendar` creates or rotates it (the old link then 404s);
  `DELETE` turns the feed off.
- Each event has a stable `UID` and a `SEQUENCE` from `updated_at`, so an
  edit updates the event instead of duplicating it.
- The client builds the full URL from its own server address, because only
  the client knows how users reach the server.

## MCP server

The API hosts an MCP server at `/mcp` (streamable HTTP, `api/mcp.py`). An AI
client needs only the URL and an API key.

- **Only API keys**, checked when the client connects, so a bad key fails
  early. The server is stateless, so it works behind any proxy.
- **Tools call the REST API in the same process** with the caller's key.
  The MCP server can do exactly what the app can, with the same validation
  and ownership rules, and no second copy of the business logic.
- **The switch** ([Authentication](#authentication)): the gateway reads it on every request through `GET /auth/config`, so turning it off takes effect at once.
  The routes stay registered, so the web UI's fallback never answers `/mcp`.
- **Persona parity.** `get_persona_stats` runs `services/personas.py`, a
  Python port of the app's scoring. Both test suites run the shared fixture
  `frontend/test/fixtures/persona_parity.json`, so the two cannot drift.

`mcp_server/` is a small stdio proxy for clients that can only start a local
program. It defines no tools of its own. For setup, see
[MCP server](../user-guide/mcp-server.md).

## Hevy import

`POST /imports/hevy/workouts` and `/measurements` take Hevy's CSV exports
(`services/hevy_import.py`).

- The server groups rows into activities by `(title, start_time, end_time)`, and
  into exercises when `set_index` restarts.
- Hevy writes two timestamp formats (Android and web); the server accepts both.
- **Duplicates by content.** Hevy gives every export the same file name, so
  the server records the file's SHA-256. The same content again gets `409`,
  unless `?force=true`.
- The test fixtures are synthetic, so no real person's history is in the
  repository.

### Guessing metadata for created exercises

A Hevy title that matches no catalog exercise becomes a custom exercise.
`services/hevy_exercise_infer.py` then guesses its equipment and muscles,
deterministically (no network, no LLM): equipment from the title's suffix or
words, muscles from the most similar seeded exercises, then from movement
keywords, else it leaves them empty rather than wrong. Only seeded exercises serve as neighbors, so the result does not depend on earlier imports. The response
flags each guess, and the app asks the user to review them.

## Intervals.icu import

A one-time import of chosen activities from the Intervals.icu API, not a sync
(`services/intervals_*.py`).

- **Two `POST` steps.** `preview` lists the activities in a date window and
  writes nothing; `activities` imports the chosen ids. The import fetches the
  window again rather than trusting the client.
- **The user's API key** travels in the body, serves that request only,
  and is never stored or returned. A test checks this.
- **A rejected key is `400`, not `401`**, because the app logs out on a `401`,
  and this error is not about the Dinatos session.
- **Duplicates per activity**, because Intervals.icu ids are stable (unlike a
  Hevy file). `IntervalsImportedActivity` is unique on `(owner_id,
  intervals_id)`, which also catches overlapping date ranges. A repeat gets
  `409` unless `?force=true`. The lookup joins to the activity, because SQLite
  (in the tests) has no cascade: deleting an imported activity allows a
  re-import.
- **Possible duplicates of Hevy workouts** (Hevy can sync to Intervals.icu):
  the preview flags activities that start within 30 minutes of an existing
  one. This is advice only; the server never skips a selected activity.
- The tests fake Intervals.icu with an `httpx2.MockTransport`; none uses the
  network.

## Exercise tutorials

`GET /exercises/{id}/tutorial` returns images or a GIF, instructions, muscles
and equipment. Providers implement `TutorialProvider`
(`services/tutorials/`), and `source` in the response names the one that
answered.

| Provider | When | Notes |
| --- | --- | --- |
| `free-exercise-db` | Default | The vendored public-domain dataset (`data/free_exercise_db.json`, see `NOTICE.md`). It also seeds the catalog of a new instance, so names always match. |
| [WorkoutX](https://workoutxapp.com) | Per user, opt-in | Animated GIFs with the user's own API key (`PATCH /profile`). |

- **No instance-wide WorkoutX key**: one user's lookups are never billed to
  another user.
- **The server keeps the key as is, and the key is write-only**, because the server sends it on every lookup. `GET /profile` reports only `has_workoutx_api_key`.
- **The server proxies GIFs** through `/exercises/media/workoutx/<id>.gif`, because
  the GIF URLs need the key in a header that an `<img>` cannot send, and a key
  in a URL would leak to logs.
- **Fallback**: if WorkoutX fails, the bundled dataset answers, so opting in
  never loses a tutorial.
- **The cache is in memory only.** The terms of WorkoutX forbid bulk caching, so the server fetches tutorials one at a time, when a user opens one.

## Container image

The image builds the web app too; see
[Releases and packaging](../development/releases.md#the-docker-image-builds-its-own-frontend).

- The container runs as a non-root UID. `docker-entrypoint.sh` runs
  `alembic upgrade head`, then `exec`s uvicorn, which is PID 1 and stops
  cleanly on `SIGTERM`.
- The Flutter version is not pinned, because nothing else pins it (CI uses
  `channel: stable`).
- The final `uv sync` needs `--no-editable`. See `AGENTS.md`.

### Serving the bundled web app

`_mount_web_ui` (`main.py`) mounts the web build at `/` only if
`Settings.web_dir` exists, which is true in the image and false in tests and
`just backend run`. The server mounts it last, so API routes always win, and it falls
back to `index.html` on a 404. The web build calls the origin that served it,
so it needs no `API_BASE_URL` (see [Clients](../deploy/clients.md) for a
separate origin).
