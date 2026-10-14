# Backend

How the API in `backend/` works and why: endpoints, authentication, backup,
imports, tutorials, MCP, and the container image. For contributors; read the
[domain model](domain-model.md) first for the terms used here.

Stack: FastAPI, async SQLAlchemy, pydantic, Postgres. Code is under
`backend/src/dinatos_backend/` (`models/`, `schemas/`, `services/`,
`api/routers/`).

## API surface

Except `GET /health`, `/auth/*` and the calendar feed, every endpoint needs
`Authorization: Bearer <token>` and only sees the caller's own data. The
token is a login session token from `/auth/login` or an API key (see
[Authentication](#authentication) and [API keys](#api-keys)).

| Endpoint | Notes |
| --- | --- |
| `/auth/register`, `/login`, `/me`, `/logout`, `/config` | See [Authentication](#authentication). |
| `/exercises` | CRUD plus `?search=` (powers the exercise picker). Global: all users share one catalog. `PATCH`/`DELETE` on a built-in exercise (`is_custom=False`) is a 403. |
| `/exercises/{id}/tutorial` | GIF plus instructions. See [Exercise tutorials](#exercise-tutorials). |
| `/exercises/{id}/records` | The caller's all-time best weight and reps. Warm-up sets never count. |
| `/exercises/{id}/history` | The caller's past sessions of it, newest first, one entry per activity. |
| `/routines` | Templates, owner-scoped. Nested exercises and sets are created and replaced as a whole (`POST`, `PUT`). No endpoint patches a single set. |
| `/activities` | Performed sessions, owner-scoped, same nested shape, plus `?since=`/`?until=`. `POST` is idempotent, see [Retried saves](#retried-saves). |
| `/profile` | One row per user (`GET`/`PATCH`, no id in the path). |
| `/measurements` | Dated body measurements, owner-scoped. |
| `/planned-workouts` | The training calendar. |
| `/profile/calendar` | Manage the calendar feed secret. See [Calendar feed](#calendar-feed). |
| `/api-keys` | See [API keys](#api-keys). |
| `/imports/hevy/*`, `/imports/intervals/*` | See [Hevy import](#hevy-import), [Intervals.icu import](#intervalsicu-import). |
| `/admin/*` | Admin only: users, backup, restore. |
| `/profile/export`, `/profile/import`, `DELETE /profile/data` | Per-user data. See [Backup and data export](#backup-and-data-export). |
| `/mcp` | MCP server. See [MCP server](#mcp-server). |

Details worth knowing:

- Exercises are global, but records and history are per caller. The app
  derives "last time", suggestions, personal records and the progress chart
  from them.
- An activity may reference one of the caller's own routines. Referencing
  someone else's is a 404, the same as reading it directly.
- Measurements are one flat row per entry with every value nullable (weigh-in
  totals, segmental analysis, tape circumferences). One weigh-in is one dated
  entry, and the backup is generic over columns. The grouping is only in the UI.
- A planned workout is not an activity (activities feed stats). To start a
  workout from a plan, the client sends `planned_workout_id` with
  `POST /activities`; the server sets the plan's `completed_activity_id`. An
  unknown id is ignored rather than failing the save.
- Routine and activity exercises carry a `superset_group`. The client keeps
  groups coherent, see [Frontend](frontend.md#supersets).

### Retried saves

A client on a flaky connection cannot tell "the request never arrived" from
"it was stored but the response was lost", so it retries. To avoid storing
the workout twice, `POST /activities` treats a request from the same caller
with the same title, start and end as a replay of the first save. It returns
the existing activity with `200` instead of `201`.

No idempotency-key column is needed: a live workout's start time is a
full-precision device timestamp, so different workouts do not collide.
Because the title is part of the key, the app freezes the title once an
attempt may have gone through, see
[Frontend](frontend.md#saving-offline).

## API documentation

FastAPI serves the generated schema at `/docs` (Swagger UI), `/redoc` and
`/openapi.json`. The routers and schemas are the source of truth, so it
cannot drift. `main.py` only adds a description and `openapi_tags`.

The app shows the same page (Profile -> "API documentation"). On web it is an
iframe of `<server>/docs`. Elsewhere, or if the browser refuses the frame, it
shows the URLs with a copy button. A browser refuses the frame when an HTTPS
page frames an HTTP backend (mixed content).

Gotchas:

- The app reaches this screen with `context.go`, not `context.push`. `push`
  leaves the address bar on `#/profile`, so the link cannot be copied,
  bookmarked or reloaded. A router-state unit test does not catch this; only
  a real browser does. `go` leaves nothing to pop, hence the screen's own
  back button.
- The app route is `/#/docs` (Flutter web uses hash routing). A bare `/docs`
  is the backend's own page. Keep the two apart if you serve both from one origin.
- Swagger UI loads its JS and CSS from `cdn.jsdelivr.net`. Air-gapped, the
  frame renders empty (console: `SwaggerUIBundle is not defined`).
  `/openapi.json` is unaffected. Vendoring `swagger-ui-dist` would fix it at
  the cost of a copied bundle and license to keep in sync. See
  [Browsing the API documentation](../deploy/quickstart.md#api-documentation).

## Authentication

Accounts are multi-user. Anyone can `POST /auth/register` unless
`DINATOS_ALLOW_REGISTRATION=false`. The first account on a fresh instance
becomes admin and can always register, so a locked-down instance can still be
bootstrapped. Admins can create accounts with `POST /admin/users` regardless
of the flag (`/admin/*` sits behind the `require_admin` dependency).
`GET /auth/config` is the public endpoint the login screen reads to decide
whether to show "Register". `POST /auth/login` returns a bearer token.

### Sessions

Each login creates an `AuthSession` row (a server-side session). The token is
a random high-entropy string (`services.auth.generate_session_token`). Only
its SHA-256 is stored. Every request hashes the presented token and looks the
session up (`services.auth.get_valid_session`).

Why not a signed JWT: a stateless token cannot be revoked before it expires,
so `POST /auth/logout` could not honestly do anything. The app also loads the
`User` row on every request anyway (so a deleted account stops working at
once), so a signed token saved no database work. Do not reintroduce JWT
machinery (`pyjwt`, a signing-key setting) without weighing that.

- `POST /auth/logout` revokes exactly the session its token names
  (`AuthSession.revoked_at`). The account's other sessions stay open.
- A revoked, expired or unknown session gives the same `401` and message.
  The response never reveals which.
- Expiry is checked in SQL (`expires_at > func.now()`), not in Python. This
  avoids timezone-awareness mismatches between the driver and Python.
- The default lifetime is 30 days (`session_ttl_days`). It is long because
  sessions are revocable: revoking (logout, or deleting the `AuthSession`
  row of a stolen device) is the real mitigation, and the TTL is a backstop.
  This avoids forcing a re-login mid-workout.

### Password and token hashing

| Secret | Hash | Why |
| --- | --- | --- |
| Password | Argon2 (`argon2-cffi`) | Passwords are low-entropy. A fast hash would let anyone who steals `users.password_hash` brute-force it. Argon2 is slow on purpose. |
| Session token, API key | Plain SHA-256 | Already 256 bits of randomness, nothing to brute-force. Argon2 would only add request latency. |

Never swap the two.

## API keys

A person can create named API keys (`POST /api-keys`; Settings -> API keys in
the app) so tools, chiefly the [MCP server](#mcp-server), act as them without
holding a password or login session.

- A key is `dnk_` plus 32 random bytes. Only its SHA-256 is stored
  (`models/api_key.py`, `services/api_keys.py`).
- The create response is the only time the key is shown. Listing returns the
  name, created and last-used times, and the last three characters
  (`suffix`).
- Deleting a key revokes it at once.
- `last_used_at` is refreshed at most once a minute, so using a key is not a
  write on every request.
- Limit: 25 keys per account.

`get_current_user` (`api/deps.py`) accepts either credential: the `dnk_`
prefix selects the key lookup, anything else the session lookup.
`get_session_user` accepts a login session only. It guards key management
(a leaked key cannot mint more or hide itself), logout, and every `/admin/*`
route (a key cannot back up or restore the server).

## Backup and data export

Two features share one idea, a versioned JSON document with `format`,
`format_version`, `exported_at` and `app_version` (`schemas/backup.py`). They
differ in everything else.

### Full server backup (admin only)

`GET /admin/backup` downloads every table as `{"tables": {name: [row, ...]}}`.
`POST /admin/backup/restore` (multipart `file` plus form field
`confirm=true`; without it, a 400 and nothing is read) resets the whole
server to that document. Code: `services/backup.py`.

- **Generic over table metadata.** Every column of every table in
  `BACKED_UP_TABLES` is exported with its original primary key, enums as
  their value, timestamps as UTC ISO 8601.
  - A new column needs no change here. A column added after a backup was
    made is filled from its nullable/default on restore.
  - A new table does: `tests/services/test_backup_coverage.py` fails until
    the table is in `BACKED_UP_TABLES` or in `EXCLUDED_TABLES` with a reason.
  - Bump `FORMAT_VERSION` (`schemas/backup.py`) only for a change an old
    reader cannot interpret (a column or table removed or re-meant).
- **Validate, then replace.** `parse_backup` checks the whole document
  before touching the database: format name and version, exact table set,
  each column's presence/type/length/enum, primary-key uniqueness, every
  foreign key resolving, and at least one admin (a backup that would lock
  everyone out is refused). Problems give a 422 listing all of them.
  `restore_backup` then deletes every table (children first) and inserts the
  document (parents first) in one transaction. If the database still rejects
  something, everything rolls back.
- **Postgres sequences.** Inserting explicit ids leaves serial sequences
  behind, so the next normal insert would collide. `reset_sequences` runs
  `setval(pg_get_serial_sequence(...), max(id)+1)` per autoincrement key, on
  Postgres only (sqlite derives the next rowid from the table). The SQL is
  unit-tested and the dialect switch is tested with a stub, but no test runs
  it against a real Postgres.
- **Secrets.** The file contains password hashes and stored WorkoutX API
  keys in the clear, because a restore must give a working server. Treat it
  as a credential.
- **Sessions.** `auth_sessions` is excluded: a row is a live login, so
  backups must not carry them and restores must not resurrect them. After a
  restore every login is gone, except the calling admin's own session, kept
  only if the backup has a user with the same id **and** the same email
  (`session_kept` in the response). Id alone is not enough: on a fresh
  instance the backup's user 1 may be a different person. Otherwise the
  caller gets a 401 on their next request, like everyone else.

### A user's own data (`/profile/export`, `/profile/import`)

Code: `services/user_export.py`. Not generic: a hand-shaped, id-free
document (`UserExport`) of profile settings, the exercises the data uses,
routines, activities and body measurements. It never contains the password
hash, sessions, import records, the calendar token or the WorkoutX API key
(a credential that stays on the server it was typed into; an import ignores
one if a file includes it).

- **Exercises are global**, so "the user's custom exercises" means those
  their routines and activities reference. They travel with their definition
  and are matched on import by exact name: an existing exercise (built-in or
  custom) is reused and never modified; an unknown name becomes a custom
  exercise. An exercise the file does not define and the server lacks is a 422.
- **Ids are remapped.** The file contains no database ids. An activity names
  its routine by `routine_ref`, the routine's 1-based position in the file's
  `routines`.
- **Merge (default)** keeps everything in the account and skips what is
  already present, so importing twice is harmless. Present means: same
  routine name; same activity title and start time; same measurement
  timestamp. Presence is judged against the account as it was before the
  import, so two same-named routines inside one file both arrive. An activity
  whose routine was skipped is linked to the existing routine.
- **Replace** (`?mode=replace`) first deletes the caller's routines,
  activities and measurements. Profile settings are applied in both modes.
- `DELETE /profile/data` clears the account: routines, activities,
  measurements, import records, and every custom exercise that no remaining
  routine or activity (anyone's) references. Exercises are shared, so one
  another account uses survives. Settings and the user stay.
- Every row written gets `owner_id` set to the caller; nothing else is
  touched. A file is fully validated (shape by pydantic, then references)
  before the first write, and applied in one transaction.

### When you add a table or column

- New table: add it to `BACKED_UP_TABLES` (the coverage test forces this).
- New user-owned field: also add it to the `Exported*` models in
  `schemas/backup.py` and to `services/user_export.py`. No test can know a
  column is user-portable, so this is on you.
- Extend `tests/backup_seed.py` with a value for it. The roundtrip tests in
  `tests/api/test_user_export_roundtrip.py` compare whole documents.

## Calendar feed

`GET /calendar/{token}.ics` serves the caller's planned workouts as an
iCalendar document (`services/calendar.py`) that Google, Apple and Outlook
calendars subscribe to by URL.

Calendar apps cannot log in, so this is the one unauthenticated data route.
The unguessable token in the path (`UserProfile.calendar_token`,
`secrets.token_urlsafe(32)`) is the credential.

- It is stored in the clear, unlike an API key, because it is shown again so
  the person can re-copy the link. It is therefore excluded from the per-user
  export but, like every profile column, included in the admin backup.
- `POST /profile/calendar` creates or rotates it (the old link then 404s).
  `DELETE` turns the feed off.
- The document is generated on every request, so it is never stale. The feed
  asks subscribers to re-fetch hourly (`REFRESH-INTERVAL`,
  `X-PUBLISHED-TTL`); Google Calendar polls only every several hours anyway.
- Events have a stable `UID` (`planned-<id>@dinatos`) and a `SEQUENCE` from
  `updated_at`, so an edit updates the event instead of duplicating it, plus
  a `VALARM` from the reminder lead time. The feed covers the last 90 days onward.
- The client builds the full URL (`<server>/calendar/<token>.ics`) from its
  own server address, since only it knows how the server is reached.

## MCP server

MCP (Model Context Protocol) lets an AI client call tools on a server. The
API hosts one at `/mcp` (streamable HTTP, `api/mcp.py`), so a client needs
only the server URL and an API key.

- **Stateless:** the key travels with every request, so it works behind any proxy.
- **Auth:** `McpGateway` accepts only `dnk_` API keys and checks them against
  the database up front, so a bad key fails at connection time.
- **Tools call the REST API in-process** with that same key over an ASGI
  transport. The MCP therefore does exactly what the app can for that person,
  with the same validation and ownership rules, and no second copy of the
  business logic.
- **Lifecycle:** the app's lifespan starts and stops the transport
  (`McpGateway.running()`). A fresh one is built each time so tests can start
  it per test.
- **Tools:** thin wrappers over exercises, routines and activities; planned
  workouts (`list_planned_workouts`, `schedule_workout`,
  `update_planned_workout`, a `PATCH` where only passed arguments change, and
  `delete_planned_workout`); and `get_persona_stats`.
- **Persona parity:** `get_persona_stats` runs `services/personas.py`, a
  Python port of the app's on-device persona scoring
  (`frontend/lib/features/personas/`). Both test suites run a shared fixture,
  `frontend/test/fixtures/persona_parity.json`. Change the scoring in one
  place and the other's test fails until it matches.

`mcp_server/` (package and entry point `dinatos-mcp`) is a small stdio proxy
to `/mcp`, for clients that can only launch a local program. It defines no
tools, so it cannot disagree with the server. It is configured only by
`DINATOS_MCP_BASE_URL` and `DINATOS_MCP_API_KEY`; there is no password or
session option. It is its own `uv` project and imports `dinatos_backend` only
in its tests, which run it against the real app in-process. To point a client
at either, see [MCP server](../user-guide/mcp-server.md).

## Hevy import

[Hevy](https://www.hevyapp.com) is a workout-tracking app.
`POST /imports/hevy/workouts` and `/imports/hevy/measurements` take its CSV
exports (Settings -> Export in Hevy) as a multipart upload. User-facing flow:
[Importing from Hevy](../user-guide/hevy-import.md).

- **Parsing.** The workout CSV has one row per set. Rows are grouped into
  activities by `(title, start_time, end_time)` and into exercises by
  watching `set_index` reset to `0`. See `services/hevy_import.py`.
- **Timestamps.** Hevy writes two formats: Android `1 Jan 2026, 08:00` and
  web/PC `Jan 1, 2026, 8:00 AM`. `_parse_timestamp` accepts both, and tests
  are parametrized over both.
- **Fixtures.** `backend/tests/fixtures/hevy_*.csv` are synthetic (warm-ups,
  dropsets, supersets, bodyweight, cardio) so nobody's real history is in a
  public repo.
- **One-shot, not a sync.** The file's SHA-256 (not its name; Hevy names every
  export the same) is recorded as a `HevyImportRecord`. Re-importing identical
  content gives `409 Conflict` naming when and under what filename it was
  imported. `?force=true` imports it anyway. A changed file is not a
  duplicate.
- **App side.** Profile -> "Import from Hevy" (`frontend/lib/features/imports/`).
  `HevyImportRepository` turns the `409` into a typed
  `HevyImportAlreadyDoneException`, shown as a confirm dialog that retries with
  `?force=true`.

### Guessing metadata for created exercises

Hevy's CSV has only an exercise title. A title matching nothing in the seeded
catalog (`services/hevy_exercise_match.py`) becomes a custom exercise, and
`services/hevy_exercise_infer.py` guesses its metadata. It is deterministic
and makes no network or LLM call.

- **Equipment:** from Hevy's parenthesised suffix ("Row (Dumbbell)") mapped to
  the `Equipment` enum. An unknown suffix is ignored. Equipment words in the
  name ("Dumbbell Row") are the fallback.
- **Muscles:** from the most similar seeded exercises. Names are compared as
  word sets with equipment and filler words removed (Dice coefficient,
  threshold 0.6). Up to three neighbours vote, weighted by similarity. If none
  qualifies, an ordered movement-keyword table is tried (row -> back,
  curl -> biceps, ...). If that also fails, muscles stay empty rather than wrong.
- Only seeded exercises are neighbours, never a person's own or earlier
  guesses, so a result does not depend on what else was imported.
- The workouts response lists each created exercise in `created_exercises`
  with `equipment_guessed` and `muscles_guessed` flags. The app shows a
  "please review these" card linking to each edit screen.
- Re-importing creates and infers nothing: existing exercises, including
  ones the person edited, are never re-inferred.

## Intervals.icu import

[Intervals.icu](https://intervals.icu) is a training-analytics service. This
is a one-time import of chosen activities from it, for someone who also
tracks there. Like Hevy it is a one-shot migration, not a sync, but the
source is an API, which changes how duplicates are caught. Nothing runs in
the background. User-facing flow: [Intervals.icu import](../user-guide/intervals-import.md).

Code: `services/intervals_client.py` (HTTP), `services/intervals_import.py`
(mapping, selection, duplicates), `api/routers/intervals_imports.py`,
`models/intervals_import.py`.

### Two steps, both `POST`

1. `POST /imports/intervals/preview` fetches activities in a date window
   (`oldest`; `newest` defaults to today) and returns them annotated. It
   writes nothing.
2. `POST /imports/intervals/activities` takes the same window plus
   `activity_ids` (the selection) and imports exactly those.

- The import re-fetches the window instead of trusting data sent by the
  client, so what is written is always what Intervals.icu says. An id missing
  from the window, or unimportable, is a `422` and nothing is written.
- Both are `POST` because the API key travels in the body. It is used for
  that request and never stored: not in the profile, a backup or an export,
  and never echoed (a test checks this).
- The athlete id must match `^(0|i?\d+)$` because it becomes a URL path
  segment. The base URL is a constant, so the endpoint cannot be pointed at
  another host.
- A key Intervals.icu rejects returns `400`, deliberately not `401`: the app
  logs the user out on a 401 from this API, and this is not their Dinatos
  session. Intervals.icu being down is a `502`.

### Mapping

- Each activity becomes one `Activity` (title from its name, start from
  `start_date_local`, end from elapsed time) with one exercise named for its
  sport, holding one set with the moving time and distance.
- Sport names come from a small table (`Run` -> "Running"); otherwise the type
  is split on capitals. An exercise of that exact name is reused, else a
  custom one is created tracking duration (and distance if any selected
  activity had it).
- There is no per-exercise strength data, so `WeightTraining` is just a timed entry.
- Timestamps are stored as naive wall-clock time, like Hevy's.
- Strava-sourced activities arrive from Intervals.icu as a stub (an `id` and
  a `_note`). They are listed as unimportable, not dropped, so the person
  sees why they are missing.

### Duplicate handling: per activity, not per file

A Hevy export has no ids, so a whole-file hash is the only check. An
Intervals.icu activity has a stable id, so each import is recorded per
activity in `IntervalsImportedActivity`: unique on `(owner_id, intervals_id)`,
pointing at the `Activity` it created. This also catches overlapping date
ranges, which a file hash cannot.

- A request including an already-imported activity is rejected whole with
  `409` (nothing written) naming those ids and import times. `?force=true`
  imports them again, creating a second `Activity` and repointing the
  existing record at it.
- Duplicates are scoped per `owner_id`.
- The selection is written in one transaction. If two requests race, the
  unique constraint makes the loser fail at commit; it is rolled back and
  reported as the same `409`.
- A record counts only while its `Activity` still exists (the lookup joins to
  it; sqlite, which tests use, has no cascade to rely on). Deleting an
  imported activity makes it importable again without `force`. For the same
  reason the records are deleted with activities in `replace` and in
  `DELETE /profile/data`.

**Overlap with Hevy.** Hevy can sync to Intervals.icu, so the same workout may
already be in Dinatos. The preview flags (`possible_duplicate_of`, the title
found) any activity starting within 30 minutes (`DUPLICATE_WINDOW`) of an
existing one for the same owner, and the app leaves it unticked. This is
advisory only: the backend never skips a selected activity for it, because
only the person knows if it is the same session.

### Backup and app

- The records table is in `BACKED_UP_TABLES` (restores keep their `activities`
  foreign keys) but not in the per-user export, like Hevy's.
- App code: `frontend/lib/features/imports/intervals_import_*` (Profile ->
  Import from Intervals.icu). The list ticks only what is importable, not
  already imported and not a possible duplicate. It remembers the key and
  window used for the fetch so later form edits do not leak into the import.
  A `409` (`IntervalsAlreadyImportedException`) opens the same "import again
  anyway?" dialog as Hevy.
- Tests fake Intervals.icu with an `httpx2.MockTransport` injected via the
  `get_intervals_client` dependency. No test touches the network.

## Exercise tutorials

`GET /exercises/{id}/tutorial` returns images or a GIF plus
instructions, muscles and equipment, from the active provider. The response's
`source` says which provider answered; the app shows it under the images.

| Provider | When | Notes |
| --- | --- | --- |
| `free-exercise-db` | Default, no setup | Vendored public-domain dataset from [yuhonas/free-exercise-db](https://github.com/yuhonas/free-exercise-db) (`backend/src/dinatos_backend/data/free_exercise_db.json`; provenance and license in that directory's `NOTICE.md`). Static JPGs. It also seeds a new instance's `exercises` table (`services.exercise.bootstrap_default_exercises`), so names match exactly and lookup by name always hits. |
| [WorkoutX](https://workoutxapp.com) | Opt-in per user | Real animated GIFs. The user saves their own API key in Settings (`PATCH /profile`, stored in `user_profile.workoutx_api_key`). |

WorkoutX design decisions:

- **No instance-wide key.** The project never holds a shared key, and one
  user's lookups are never served from or billed to another's account.
- **Key stored as-is and write-only.** It must be sent to WorkoutX on every
  lookup, so a hash would be useless. `GET /profile` only reports
  `has_workoutx_api_key`.
- **GIFs are proxied.** WorkoutX GIF URLs also need the key, and an `<img>` or
  Flutter `Image.network` cannot send the `X-WorkoutX-Key` header (nor should
  a key go in a query string, where it leaks to the client and logs). The
  provider rewrites each GIF URL to `/exercises/media/workoutx/<id>.gif`, an
  authenticated endpoint that fetches the GIF with the caller's key and streams
  it back through the app's normal bearer-token client.
- **Fallback.** `FallbackTutorialProvider` (`services/tutorials/fallback.py`)
  answers from free-exercise-db if WorkoutX fails (bad key, quota, outage) or
  has no match, so opting in never loses a tutorial. The failure is logged as
  a server warning.

Providers implement the `TutorialProvider` protocol
(`services/tutorials/base.py`), so a new one is a new adapter.
`services.tutorials.get_tutorial_provider_for_key` picks one per request:
WorkoutX for users with a saved key (one cached provider per distinct key),
the bundled dataset otherwise.

**Cache.** Every lookup goes through an in-memory cache
(`services/tutorials/cache.py`) that lives for the process only and is
deliberately never persisted. WorkoutX's terms prohibit bulk-caching or
scraping, so tutorials are fetched one at a time, only when someone opens
one, never as a catalog sync. A persistent cache would also bring staleness,
reconciliation and licensing questions about storing someone else's data. A
restart costs one re-fetch per exercise viewed.

## Container image

The root `Dockerfile` (build context: the repo root, since it also needs
`frontend/`) has three stages:

1. `frontend-builder` downloads Flutter's current `stable` and runs
   `flutter build web --release`.
2. `builder` resolves and installs the backend with `uv`.
3. `runtime` is a slim image with the backend venv from `builder` and
   `build/web` from `frontend-builder`, placed at `web/` under `/app`, where
   `Settings.web_dir` expects it.

It runs as a non-root numeric uid. `docker-entrypoint.sh` runs
`alembic upgrade head` and then `exec uvicorn ...`, so uvicorn is PID 1 and
shuts down cleanly on `SIGTERM`.

- **No pinned Flutter version.** Nothing else in the repo pins one either (CI
  and the release workflow use `subosito/flutter-action@v2` with
  `channel: stable`), so a pin here would be a second source of truth. The
  stage asks Google's `releases_linux.json` feed which archive `stable` is
  and downloads that.
- **`--no-editable` is required** on the final `uv sync --locked --no-dev`.
  The default editable install points at the builder's `/app/src`, which does
  not exist in `runtime`, so `import dinatos_backend` fails at container
  start. `docker build` still succeeds; only running the image shows it. See
  `AGENTS.md`.

`docker-compose.yml` wires the image to Postgres; see
[Deploying with Docker Compose](../deploy/quickstart.md). `just docker debug`
attaches [`nicolaka/netshoot`](https://github.com/nicolaka/netshoot) (ping,
dig, tcpdump, curl, ...) to the running container's network namespace. It is
not in the `Dockerfile` on purpose, so the runtime image stays small; it is
pulled on first use.

### Serving the bundled web app

`_mount_web_ui` in `main.py` mounts a `StaticFiles` subclass (`_WebApp`) at
`/`, only if `Settings.web_dir` (default `web`, relative to the working
directory) exists. That is true in the Docker image and false everywhere else
(`just backend run`, all tests), where behaviour is unchanged.

- It is mounted last, after every API router and `/health`, so API routes
  always match first.
- `_WebApp.get_response` falls back to `index.html` on a 404. This rarely
  matters: Flutter web's hash routing (`/#/routines/1`) never sends the
  client-side route to the server, so browsers only request `/`.
- The web build needs no `--dart-define=API_BASE_URL`. `ApiConfig` defaults a
  web build to the origin that served it, which is this backend. To build
  against a separately hosted backend, see [Clients](../deploy/clients.md).
