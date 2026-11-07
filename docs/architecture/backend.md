# Backend

This page explains how the API in `backend/` works and why. It is for
contributors. Read the [domain model](domain-model.md) first for the terms
used here.

Terms: the "server" is the backend. The "app" is the Flutter app. A "client"
is the app or any other program that calls the API.

The server uses FastAPI, async SQLAlchemy, pydantic and Postgres. The code is
in `backend/src/dinatos_backend/`, in the directories `models/`, `schemas/`,
`services/` and `api/routers/`.

## API surface

These routes do not need a token: `GET /health`, `/auth/*` and the calendar
feed. Every other endpoint needs the header `Authorization: Bearer <token>`.
It only shows the data of the caller.

The token is a login session token from `/auth/login` or an API key. See
[Authentication](#authentication) and [API keys](#api-keys).

| Endpoint | Notes |
| --- | --- |
| `/auth/register`, `/login`, `/me`, `/logout`, `/config` | See [Authentication](#authentication). |
| `/exercises` | CRUD and `?search=` (the exercise picker uses it). All users share one catalog. `PATCH` or `DELETE` on a built-in exercise (`is_custom=False`) returns 403. |
| `/exercises/{id}/tutorial` | A GIF and instructions. See [Exercise tutorials](#exercise-tutorials). |
| `/exercises/{id}/records` | The best weight and reps of the caller, for all time. Warm-up sets never count. |
| `/exercises/{id}/history` | The past sessions of the caller for the exercise, newest first, one entry for each activity. |
| `/routines` | Templates. Each belongs to one owner. `POST` and `PUT` create and replace the nested exercises and sets as a whole. No endpoint changes a single set. |
| `/activities` | Performed sessions. Each belongs to one owner and has the same nested shape. Accepts `?since=` and `?until=`. `POST` is idempotent. See [Retried saves](#retried-saves). |
| `/profile` | One row for each user. `GET` and `PATCH` with no id in the path. |
| `/measurements` | Dated body measurements. Each belongs to one owner. |
| `/planned-workouts` | The training calendar. |
| `/profile/calendar` | Manages the secret of the calendar feed. See [Calendar feed](#calendar-feed). |
| `/api-keys` | See [API keys](#api-keys). |
| `/imports/hevy/*`, `/imports/intervals/*` | See [Hevy import](#hevy-import) and [Intervals.icu import](#intervalsicu-import). |
| `/admin/*` | Admin only: users, backup and restore. |
| `/profile/export`, `/profile/import`, `DELETE /profile/data` | Data of one user. See [Backup and data export](#backup-and-data-export). |
| `/mcp` | The MCP server. See [MCP server](#mcp-server). |

Important details:

- All users share the exercises, but records and history are different for
  each caller. The app uses them to show "last time", suggestions, personal
  records and the progress chart.
- An activity can refer to a routine of the caller. If it refers to the
  routine of another user, the server returns 404. This is the same result as
  a direct read.
- A measurement is one flat row for each entry. Every value can be null:
  weigh-in totals, segmental analysis and tape circumferences. One weigh-in
  is one dated entry. The backup works on columns in a generic way. Only the
  UI groups the values.
- A planned workout is not an activity, because activities feed the
  statistics. To start a workout from a plan, the client sends
  `planned_workout_id` with `POST /activities`. The server then sets
  `completed_activity_id` of the plan. If the id is unknown, the server
  ignores it and the save does not fail.
- Routine exercises and activity exercises have a `superset_group`. The
  client keeps the groups consistent. See [Frontend](frontend.md#supersets).

### Retried saves

On an unreliable connection, a client cannot know if a request never arrived
or if the server stored it and the response was lost. So the client sends the
request again.

To prevent a double save, `POST /activities` compares each request with the
earlier ones. If the same caller sent the same title, start time and end
time, the server treats the request as a replay. It returns the existing
activity with status `200` instead of `201`.

An idempotency-key column is not necessary. The start time of a live workout
is a device timestamp with full precision, so different workouts do not
collide.

The title is part of the key. For this reason, the app freezes the title when
an attempt can already have succeeded. See
[Frontend](frontend.md#saving-offline).

## API documentation

FastAPI serves the generated schema at `/docs` (Swagger UI), `/redoc` and
`/openapi.json`. The routers and schemas are the source of truth, so this
documentation cannot become different from the code. `main.py` only adds a
description and `openapi_tags`.

The app shows the same page (Profile -> "API documentation"):

- On web, the page is an iframe of `<server>/docs`.
- On other platforms, the app shows the URLs with a copy button.
- If the browser refuses the frame, the app also shows the URLs. A browser
  refuses the frame when an HTTPS page frames an HTTP backend (mixed
  content).

Known problems:

- The app opens this screen with `context.go`, not `context.push`. `push`
  leaves the address bar on `#/profile`. Then the user cannot copy, bookmark
  or reload the link. A unit test of the router state does not find this
  problem. Only a real browser finds it. `go` leaves nothing to pop, so the
  screen has its own back button.
- The app route is `/#/docs`, because Flutter web uses hash routing. A plain
  `/docs` is the page of the backend. If you serve both from one origin, keep
  them apart.
- Swagger UI loads its JS and CSS from `cdn.jsdelivr.net`. Without internet
  access, the frame is empty. The console shows `SwaggerUIBundle is not
  defined`. `/openapi.json` still works. To fix this, you can vendor
  `swagger-ui-dist`. But then the project must keep a copy of the bundle and
  its license in sync. See
  [Browsing the API documentation](../deploy/quickstart.md#api-documentation).

## Authentication

The server supports many accounts. Anyone can call `POST /auth/register`,
unless `DINATOS_ALLOW_REGISTRATION=false`. The first account on a new
instance becomes the admin. This account can always register, so you can set
up an instance that has registration off.

An admin can create accounts with `POST /admin/users`, also when the flag is
off. The `require_admin` dependency protects `/admin/*`.

`GET /auth/config` is a public endpoint. The login screen reads it to decide
if it shows "Register". `POST /auth/login` returns a bearer token.

### Sessions

Each login creates an `AuthSession` row. This row is a server-side session.
The token is a random string with high entropy
(`services.auth.generate_session_token`). The server stores only the SHA-256
hash of the token. For each request, the server hashes the token it receives
and looks for the session (`services.auth.get_valid_session`).

The server does not use a signed JWT, for two reasons:

- The server cannot revoke a stateless token before it expires. So
  `POST /auth/logout` could not do anything real.
- The server loads the `User` row for every request. This makes a deleted
  account stop working at once. So a signed token does not save a database
  read.

Do not add JWT code (`pyjwt`, a setting for a signing key) before you
consider these two reasons.

Session rules:

- `POST /auth/logout` revokes the session that its token names
  (`AuthSession.revoked_at`). The other sessions of the account stay open.
- A session that is revoked, expired or unknown gives the same `401` status
  and message. The response does not show which case it is.
- The server checks the expiry in SQL (`expires_at > func.now()`), not in
  Python. This prevents timezone mismatches between the driver and Python.
- The default lifetime is 30 days (`session_ttl_days`). It is long because
  sessions can be revoked. Revoking is the real protection: the user logs
  out, or an admin deletes the `AuthSession` row of a stolen device. The
  lifetime is only a second barrier. A long lifetime also stops a forced
  login in the middle of a workout.

### Password and token hashing

| Secret | Hash | Why |
| --- | --- | --- |
| Password | Argon2 (`argon2-cffi`) | A password has low entropy. With a fast hash, a person who steals `users.password_hash` can brute-force it. Argon2 is slow on purpose. |
| Session token, API key | Plain SHA-256 | These secrets already have 256 bits of randomness, so brute force is not possible. Argon2 only adds delay to each request. |

Do not use one hash for the other secret.

## API keys

A user can create named API keys. The endpoint is `POST /api-keys`. In the
app, use Settings -> API keys. With a key, a tool acts as the user without a
password or login session. The main tool is the [MCP server](#mcp-server).

- A key is the prefix `dnk_` and 32 random bytes. The server stores only the
  SHA-256 hash (`models/api_key.py`, `services/api_keys.py`).
- The create response is the only time that shows the key. The list shows
  the name, the created time, the last-used time and the last three
  characters of the key (`suffix`).
- When a user deletes a key, the key stops working at once.
- The server updates `last_used_at` at most one time each minute. So the use
  of a key is not a write for every request.
- An account can have 25 keys at most.

`get_current_user` (`api/deps.py`) accepts both credentials. If the token has
the prefix `dnk_`, the server looks for a key. Otherwise it looks for a
session.

`get_session_user` accepts only a login session. It protects these routes:

- Key management. A leaked key cannot make more keys or hide itself.
- Logout.
- Every `/admin/*` route. A key cannot back up or restore the server.

## Backup and data export

Two features use one idea: a JSON document with a version. The document has
the fields `format`, `format_version`, `exported_at` and `app_version`
(`schemas/backup.py`). In all other points, the two features are different.

### Full server backup (admin only)

`GET /admin/backup` downloads every table as `{"tables": {name: [row, ...]}}`.

`POST /admin/backup/restore` resets the whole server to the content of such a
document. It takes a multipart `file` and the form field `confirm=true`. If
`confirm=true` is missing, the server returns 400 and does not read the file.
The code is in `services/backup.py`.

**Generic over table metadata.** The server exports every column of every
table in `BACKED_UP_TABLES`. It keeps the original primary key. It writes
enums as their value and timestamps as UTC ISO 8601.

- A new column does not need a change here. If a backup is older than the
  column, the restore fills the column from its nullable setting or default.
- A new table needs a change.
  `tests/services/test_backup_coverage.py` fails until the table is in
  `BACKED_UP_TABLES`, or in `EXCLUDED_TABLES` with a reason.
- Increase `FORMAT_VERSION` (`schemas/backup.py`) only if an old reader
  cannot understand the change. For example, a column or table is removed or
  has a new meaning.

**Validate, then replace.** `parse_backup` checks the whole document before
it changes the database. It checks these points:

- The format name and version.
- The exact set of tables.
- The presence, type, length and enum of each column.
- The uniqueness of primary keys.
- That every foreign key has a target.
- That at least one admin exists. The server refuses a backup that locks out
  all users.

If there are problems, the server returns 422 with a list of all of them.

`restore_backup` then deletes every table (children first). It inserts the
document (parents first). All of this is one transaction. If the database
rejects any row, the server rolls everything back.

**Postgres sequences.** A restore inserts explicit ids. This leaves the
serial sequences behind, so the next normal insert can collide. For each
autoincrement key, `reset_sequences` runs
`setval(pg_get_serial_sequence(...), max(id)+1)`. It does this on Postgres
only, because sqlite takes the next rowid from the table. A unit test checks
the SQL. A test with a stub checks the switch for the dialect. No test runs
the SQL against a real Postgres.

**Secrets.** Warning: the backup file contains password hashes and stored
WorkoutX API keys in clear text. A restore must produce a working server, so
it needs them. Treat the file as a credential.

**Sessions.** The backup does not include `auth_sessions`. A row in this
table is a live login. A backup must not carry it, and a restore must not
bring it back. After a restore, all logins end. One exception exists: the
session of the admin who made the restore.

The server keeps this session only if the backup has a user with the same id
and the same email. The response field `session_kept` shows the result. The
id alone is not enough, because on a new instance the user 1 of the backup
can be a different person. If the server does not keep the session, the
admin gets a 401 on the next request, like all other users.

### A user's own data (`/profile/export`, `/profile/import`)

The code is in `services/user_export.py`. This feature is not generic. The
document (`UserExport`) is shaped by hand and has no ids. It contains:

- The profile settings.
- The exercises that the data uses.
- Routines.
- Activities.
- Body measurements.

It never contains the password hash, sessions, import records, the calendar
token or the WorkoutX API key. The API key is a credential that stays on the
server where the user typed it. If a file contains one, an import ignores it.

**Exercises.** All users share the exercises. So "the custom exercises of the
user" means the exercises that the routines and activities of the user refer
to. These exercises travel with their definition. An import matches them by
exact name:

- If an exercise with this name exists (built-in or custom), the import uses
  it and does not change it.
- If the name is unknown, the import makes a custom exercise.
- If the file does not define an exercise and the server does not have it,
  the server returns 422.

**Ids.** The file does not contain database ids. An activity names its
routine with `routine_ref`. This is the 1-based position of the routine in
the `routines` list of the file.

**Merge** is the default mode. It keeps everything in the account. It skips
what is already there, so you can import the same file two times without
harm. "Already there" means:

- A routine with the same name.
- An activity with the same title and start time.
- A measurement with the same timestamp.

The server compares with the account as it was before the import. So if one
file has two routines with the same name, both arrive. If the server skips
the routine of an activity, it links the activity to the existing routine.

**Replace** (`?mode=replace`) first deletes the routines, activities and
measurements of the caller. Both modes apply the profile settings.

**Delete.** `DELETE /profile/data` clears the account. It deletes:

- Routines, activities and measurements.
- Import records.
- Every custom exercise that no remaining routine or activity references.
  A routine or activity of any user, not only the caller, keeps an exercise.

The settings and the user stay. An exercise that another account uses stays,
because the exercises are shared.

**Writes.** The server sets `owner_id` to the caller on every row it writes.
It changes nothing else. Before the first write, the server validates the
whole file: pydantic checks the shape, then the server checks the references.
It applies the file in one transaction.

### When you add a table or column

1. If you add a table, add it to `BACKED_UP_TABLES`. The coverage test
   forces this.
2. If you add a field that belongs to the user, add it also to the
   `Exported*` models in `schemas/backup.py` and to `services/user_export.py`.
   No test can know that a column is portable between users. This step is
   your responsibility.
3. Add a value for the new field to `tests/backup_seed.py`. The roundtrip
   tests in `tests/api/test_user_export_roundtrip.py` compare whole
   documents.

## Calendar feed

`GET /calendar/{token}.ics` serves the planned workouts of the caller as an
iCalendar document (`services/calendar.py`). Google, Apple and Outlook
calendars can subscribe to it with the URL.

Calendar apps cannot log in. So this is the only data route that does not
need authentication. The token in the path is the credential. It cannot be
guessed (`UserProfile.calendar_token`, `secrets.token_urlsafe(32)`).

- The server stores the token in clear text, unlike an API key. The app
  shows the link again, so the user can copy it again. For this reason, the
  per-user export does not include the token. The admin backup includes it,
  like every profile column.
- `POST /profile/calendar` creates or rotates the token. After a rotation,
  the old link returns 404. `DELETE` turns the feed off.
- The server generates the document for each request, so it is always
  current. The feed asks subscribers to fetch it again each hour
  (`REFRESH-INTERVAL`, `X-PUBLISHED-TTL`). Google Calendar fetches it only
  every few hours.
- Each event has a stable `UID` (`planned-<id>@dinatos`). It also has a
  `SEQUENCE` from `updated_at`, so an edit updates the event and does not
  duplicate it. Each event has a `VALARM` from the reminder lead time.
- The feed covers the last 90 days and all later days.
- The client builds the full URL (`<server>/calendar/<token>.ics`) from its
  own server address. Only the client knows how a user reaches the server.

## MCP server

MCP (Model Context Protocol) lets an AI client call tools on a server. The
API hosts an MCP server at `/mcp` (streamable HTTP, `api/mcp.py`). An AI
client needs only the server URL and an API key.

- **Stateless.** The key travels with every request, so the server works
  behind any proxy.
- **Authentication.** `McpGateway` accepts only `dnk_` API keys. It checks
  them in the database at the start, so a bad key fails when the client
  connects.
- **Tools call the REST API in the same process.** They use the same key
  with an ASGI transport. So the MCP server can do exactly what the app can
  do for that user. It uses the same validation and ownership rules. There
  is no second copy of the business logic.
- **Lifecycle.** The lifespan of the app starts and stops the transport
  (`McpGateway.running()`). The server builds a new transport each time, so
  a test can start it for each test.
- **Switch.** `Settings.mcp_enabled` (`DINATOS_MCP_ENABLED`, default on) is
  read for each request and in `running()`. If it is off, the transport does
  not start and `/mcp` returns 404. The routes stay registered. So the
  catch-all fallback of the web UI never answers `/mcp` with `index.html`.
- **Tools.** The tools are thin wrappers for these areas:
  - Exercises, routines and activities.
  - Planned workouts: `list_planned_workouts`, `schedule_workout`,
    `update_planned_workout` and `delete_planned_workout`.
    `update_planned_workout` is a `PATCH`: only the arguments you pass
    change.
  - `get_persona_stats`.
- **Persona parity.** `get_persona_stats` runs `services/personas.py`. This
  is a Python port of the persona scoring in the app
  (`frontend/lib/features/personas/`). Both test suites run one shared
  fixture, `frontend/test/fixtures/persona_parity.json`. If you change the
  scoring in one place, the test of the other place fails until it matches.

`mcp_server/` is a small stdio proxy to `/mcp`. Its package has the entry
point `dinatos-mcp`. It is for clients that can only start a local program.

- It defines no tools, so it cannot be different from the server.
- Only `DINATOS_MCP_BASE_URL` and `DINATOS_MCP_API_KEY` configure it. It has
  no password or session option.
- It is its own `uv` project. It imports `dinatos_backend` only in its
  tests. The tests run it against the real app in the same process.

To connect a client to the server or to the proxy, see
[MCP server](../user-guide/mcp-server.md).

## Hevy import

[Hevy](https://www.hevyapp.com) is a workout-tracking app.
`POST /imports/hevy/workouts` and `/imports/hevy/measurements` take its CSV
exports as a multipart upload. In Hevy, the export is in Settings -> Export.
For the user flow, see [Importing from Hevy](../user-guide/hevy-import.md).

- **Parsing.** The workout CSV has one row for each set. The server groups
  the rows into activities by `(title, start_time, end_time)`. It groups
  them into exercises when `set_index` resets to `0`. See
  `services/hevy_import.py`.
- **Timestamps.** Hevy writes two formats: Android `1 Jan 2026, 08:00` and
  web or PC `Jan 1, 2026, 8:00 AM`. `_parse_timestamp` accepts both. The
  tests have parameters for both.
- **Fixtures.** The files `backend/tests/fixtures/hevy_*.csv` are synthetic.
  They contain warm-ups, dropsets, supersets, bodyweight and cardio. This
  way, the real history of a person is not in a public repository.
- **One-time import, not a sync.** The server records the SHA-256 hash of
  the file as a `HevyImportRecord`. It does not use the file name, because
  Hevy gives every export the same name. If a user imports identical content
  again, the server returns `409 Conflict`. The response names the time of
  the first import and its file name. `?force=true` imports the file anyway.
  A changed file is not a duplicate.
- **App side.** The user starts the import in Profile -> "Import from Hevy"
  (`frontend/lib/features/imports/`). `HevyImportRepository` changes the
  `409` into a typed `HevyImportAlreadyDoneException`. The app shows it as a
  confirm dialog that tries again with `?force=true`.

### Guessing metadata for created exercises

The Hevy CSV has only the title of an exercise. If a title does not match an
exercise in the seeded catalog (`services/hevy_exercise_match.py`), the
import makes a custom exercise. Then `services/hevy_exercise_infer.py`
guesses the metadata of the exercise. The guess is deterministic. It does
not call the network or an LLM.

- **Equipment.** The server reads the suffix in parentheses of the Hevy
  title, for example "Row (Dumbbell)". It maps the suffix to the `Equipment`
  enum. It ignores an unknown suffix. If there is no suffix, it uses
  equipment words in the name, for example "Dumbbell Row".
- **Muscles.** The server uses the most similar seeded exercises:
  1. It compares the names as sets of words. It first removes equipment
     words and filler words. The measure is the Dice coefficient with
     threshold 0.6.
  2. Up to three neighbors vote. The votes have the weight of the
     similarity.
  3. If no neighbor qualifies, the server tries an ordered table of movement
     keywords, for example row -> back and curl -> biceps.
  4. If this also fails, the muscles stay empty. This is better than a wrong
     value.
- Only seeded exercises can be neighbors. Exercises of a user and earlier
  guesses cannot. So the result does not depend on what else the user
  imported.
- The workouts response lists each created exercise in `created_exercises`.
  Each entry has the flags `equipment_guessed` and `muscles_guessed`. The app
  shows a "please review these" card with a link to each edit screen.
- A second import creates and guesses nothing. The server never guesses
  again for an existing exercise. This includes an exercise that the user
  edited.

## Intervals.icu import

[Intervals.icu](https://intervals.icu) is a training-analytics service. A
user who also tracks there can import chosen activities from it one time.

Like the Hevy import, this is a one-time migration, not a sync. The source is
an API, and this changes how the server finds duplicates. Nothing runs in the
background. For the user flow, see
[Intervals.icu import](../user-guide/intervals-import.md).

The code is in these files:

- `services/intervals_client.py` (HTTP).
- `services/intervals_import.py` (mapping, selection, duplicates).
- `api/routers/intervals_imports.py`.
- `models/intervals_import.py`.

### Two steps, both `POST`

1. `POST /imports/intervals/preview` fetches the activities in a date window
   (`oldest`; `newest` is today by default). It returns them with
   annotations. It writes nothing.
2. `POST /imports/intervals/activities` takes the same window and
   `activity_ids` (the selection). It imports exactly those activities.

Rules for both steps:

- The import fetches the window again. It does not trust data from the
  client. So the written data is always the data that Intervals.icu gives.
  If an id is not in the window, or if it cannot be imported, the server
  returns `422` and writes nothing.
- Both steps are `POST` because the API key is in the body. The server uses
  the key for that request only. It never stores the key: not in the
  profile, a backup or an export. It never sends the key back. A test
  checks this.
- The athlete id must match `^(0|i?\d+)$`, because it becomes a segment of
  a URL path. The base URL is a constant, so the endpoint cannot point to
  another host.
- If Intervals.icu rejects the key, the server returns `400`. It does not
  return `401` on purpose, because the app logs the user out on a 401 from
  this API. This error is not about the Dinatos session. If Intervals.icu is
  down, the server returns `502`.

### Mapping

- Each activity becomes one `Activity`. The title comes from its name. The
  start comes from `start_date_local`. The end comes from the elapsed time.
  The activity has one exercise, named for its sport. The exercise has one
  set with the moving time and the distance.
- Sport names come from a small table (`Run` -> "Running"). Otherwise the
  server splits the type at capital letters.
- If an exercise with that exact name exists, the server uses it. If not, it
  creates a custom exercise. The exercise tracks duration. It also tracks
  distance if any selected activity has a distance.
- Intervals.icu has no strength data for each exercise. So `WeightTraining`
  is only a timed entry.
- The server stores timestamps as naive wall-clock time, like the Hevy
  import.
- Intervals.icu gives an activity from Strava as a stub (an `id` and a
  `_note`). The preview lists it as not importable. It does not drop it, so
  the user can see why it is missing.

### Duplicate handling: per activity, not per file

A Hevy export has no ids, so a hash of the whole file is the only check. An
Intervals.icu activity has a stable id. So the server records each import for
each activity in `IntervalsImportedActivity`. This record is unique on
`(owner_id, intervals_id)`. It points to the `Activity` that the import
created. This also finds overlapping date ranges. A file hash cannot do this.

- If a request has an activity that is already imported, the server rejects
  the whole request with `409` and writes nothing. The response names the
  ids and the import times.
- `?force=true` imports them again. It creates a second `Activity` and
  points the existing record to it.
- Duplicates are scoped to each `owner_id`.
- The server writes the selection in one transaction. If two requests race,
  the unique constraint makes the later one fail at commit. The server rolls
  it back and reports the same `409`.
- A record counts only while its `Activity` exists. The lookup joins to the
  activity, because sqlite (which the tests use) has no cascade. If a user
  deletes an imported activity, the user can import it again without
  `force`. For the same reason, the server deletes the records together with
  the activities in `replace` mode and in `DELETE /profile/data`.

**Overlap with Hevy.** Hevy can sync to Intervals.icu, so the same workout
can already be in Dinatos. The preview flags an activity if it starts within
30 minutes (`DUPLICATE_WINDOW`) of an existing activity of the same owner.
The flag is `possible_duplicate_of`, and it holds the title that the server
found. The app leaves this activity unticked.

This flag is advice only. The backend never skips a selected activity
because of it. Only the user knows if it is the same session.

### Backup and app

- The records table is in `BACKED_UP_TABLES`, so a restore keeps the foreign
  keys to `activities`. It is not in the per-user export, like the table of
  the Hevy import.
- The app code is in `frontend/lib/features/imports/intervals_import_*`. The
  user starts it in Profile -> Import from Intervals.icu.
- The app list ticks only an activity that is importable, not already
  imported and not a possible duplicate.
- The app remembers the key and window that it used for the fetch. So later
  edits to the form do not change the import.
- A `409` (`IntervalsAlreadyImportedException`) opens the same "import again
  anyway?" dialog as the Hevy import.
- The tests fake Intervals.icu with an `httpx2.MockTransport`. The
  `get_intervals_client` dependency injects it. No test uses the network.

## Exercise tutorials

`GET /exercises/{id}/tutorial` returns images or a GIF, with instructions,
muscles and equipment. The active provider supplies them. The `source` field
of the response names the provider that answered. The app shows it under the
images.

| Provider | When | Notes |
| --- | --- | --- |
| `free-exercise-db` | Default. No setup. | Vendored public-domain dataset from [yuhonas/free-exercise-db](https://github.com/yuhonas/free-exercise-db) (`backend/src/dinatos_backend/data/free_exercise_db.json`; `NOTICE.md` in that directory has the origin and license). Static JPGs. It also seeds the `exercises` table of a new instance (`services.exercise.bootstrap_default_exercises`), so the names match exactly and the lookup by name always succeeds. |
| [WorkoutX](https://workoutxapp.com) | Opt-in for each user. | Real animated GIFs. The user saves their own API key in Settings (`PATCH /profile`, stored in `user_profile.workoutx_api_key`). |

Design decisions for WorkoutX:

- **No key for the whole instance.** The project never holds a shared key.
  The lookups of one user never use, and are never billed to, the account of
  another user.
- **The key is stored as is and is write-only.** The server must send the key
  to WorkoutX for every lookup, so a hash is useless. `GET /profile` only
  reports `has_workoutx_api_key`.
- **The server proxies the GIFs.** The GIF URLs of WorkoutX also need the key.
  An `<img>` or a Flutter `Image.network` cannot send the `X-WorkoutX-Key`
  header. A key must not go in a query string either, because it then leaks
  to the client and to logs. So the provider rewrites each GIF URL to
  `/exercises/media/workoutx/<id>.gif`. This endpoint needs authentication.
  It fetches the GIF with the key of the caller. It streams the GIF back
  through the normal bearer-token client of the app.
- **Fallback.** `FallbackTutorialProvider` (`services/tutorials/fallback.py`)
  answers from free-exercise-db if WorkoutX fails or has no match. A failure
  is a bad key, a quota limit or an outage. So a user who opts in never
  loses a tutorial. The server logs the failure as a warning.

Providers implement the `TutorialProvider` protocol
(`services/tutorials/base.py`). A new provider is a new adapter.

`services.tutorials.get_tutorial_provider_for_key` picks a provider for each
request. It picks WorkoutX for a user with a saved key (one cached provider
for each different key). Otherwise it picks the bundled dataset.

**Cache.** Every lookup goes through an in-memory cache
(`services/tutorials/cache.py`). The cache lives only as long as the process.
It is never persisted, on purpose:

- The terms of WorkoutX forbid bulk caching and scraping. So the server
  fetches tutorials one at a time, and only when a user opens one. It never
  syncs the catalog.
- A persistent cache also brings stale data, reconciliation and questions
  about the license to store data of another party.

A restart costs one new fetch for each exercise that a user views.

## Container image

The root `Dockerfile` has three stages. Its build context is the repository
root, because the build also needs `frontend/`.

1. `frontend-builder` downloads the current `stable` Flutter and runs
   `flutter build web --release`.
2. `builder` resolves and installs the backend with `uv`.
3. `runtime` is a small image. It has the backend venv from `builder` and
   `build/web` from `frontend-builder`. The build puts `build/web` at `web/`
   under `/app`, where `Settings.web_dir` expects it.

The container runs as a non-root numeric uid. `docker-entrypoint.sh` runs
`alembic upgrade head` and then `exec uvicorn ...`. So uvicorn is PID 1 and
stops cleanly on `SIGTERM`.

- **No pinned Flutter version.** Nothing else in the repository pins one.
  CI and the release workflow use `subosito/flutter-action@v2` with
  `channel: stable`. A pin here would be a second source of truth. The stage
  asks the `releases_linux.json` feed of Google which archive `stable` is,
  and downloads it.
- **`--no-editable` is required** on the final `uv sync --locked --no-dev`.
  The default editable install points to `/app/src` of the builder. This path
  does not exist in `runtime`, so `import dinatos_backend` fails when the
  container starts. `docker build` still succeeds. Only a run of the image
  shows the error. See `AGENTS.md`.

`docker-compose.yml` connects the image to Postgres. See
[Deploying with Docker Compose](../deploy/quickstart.md).

`just docker debug` attaches
[`nicolaka/netshoot`](https://github.com/nicolaka/netshoot) to the network
namespace of the running container. It has tools such as ping, dig, tcpdump
and curl. The `Dockerfile` does not include it on purpose, so the runtime
image stays small. Docker pulls it at first use.

### Serving the bundled web app

`_mount_web_ui` in `main.py` mounts a `StaticFiles` subclass (`_WebApp`) at
`/`. It does this only if the directory `Settings.web_dir` exists. The default
is `web`, relative to the working directory. The directory exists in the
Docker image. It does not exist in other places (`just backend run` and all
tests), so the behavior there does not change.

- The server mounts it last, after every API router and `/health`. So API
  routes always match first.
- `_WebApp.get_response` falls back to `index.html` on a 404. This rarely
  matters. Flutter web uses hash routing (`/#/routines/1`), so the browser
  never sends the client-side route to the server. Browsers only request
  `/`.
- The web build does not need `--dart-define=API_BASE_URL`. `ApiConfig` sets
  the default of a web build to the origin that served it. This origin is
  this backend. To build against a backend on a different host, see
  [Clients](../deploy/clients.md).
