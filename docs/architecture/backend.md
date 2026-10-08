# Backend

FastAPI + async SQLAlchemy + pydantic, backed by Postgres.

## API surface

`GET /health` and `/auth/*` aside, every endpoint requires a bearer token
(`Authorization: Bearer <token>`, from `/auth/login`) and only ever sees the
calling user's own data:

- `/auth/register`, `/auth/login`, `/auth/me`, `/auth/logout` -- see
  "Authentication" below.
- `/exercises` -- full CRUD, plus `?search=` (backs the exercise picker).
  The one shared, global resource: every user's catalog is the same. `PATCH`
  and `DELETE` are a 403 against a built-in (`is_custom=False`) exercise --
  only a user-created one can be edited or deleted; see "Exercise
  tutorials" below and `Exercise.is_custom`'s docstring.
  `/exercises/{id}/tutorial` -- a GIF plus instructions/muscles/equipment,
  see "Exercise tutorials" below. `/exercises/{id}/records` -- the caller's
  own all-time best weight and reps (warm-up sets never count), and
  `/exercises/{id}/history` -- the caller's own past sessions of it, newest
  first, one entry per activity. Both are per-caller despite the exercise
  being global; the app computes "last time", suggestions, personal records
  and the progress chart from them.
- `/routines` -- saved routine templates, scoped to their owner. Nested
  exercises/sets are created and replaced as a whole (`POST`, `PUT`); there
  is no endpoint for patching one set in isolation.
- `/activities` -- performed sessions, scoped to their owner, the same
  nested create/replace shape as routines, plus `?since=`/`?until=`
  filtering. An activity may reference one of the caller's own `/routines`
  templates; referencing someone else's is a 404, the same as trying to
  read it directly. `POST` is idempotent for a retried save: see "Retried
  saves" below.
- `/profile` -- one row per user (`GET`/`PATCH`, no id in the path: always
  the caller's own).
- `/measurements` -- dated body-measurement entries, scoped to their owner.
  One flat row per entry (every value nullable), in three loose groups: the
  basics and a smart scale's totals (weight, fat %, muscle/bone mass, water %,
  BMI, visceral fat, DCI kcal, metabolic age), its segmental analysis (fat %
  and muscle kg per arm, leg and trunk) and tape circumferences. Flat rather
  than separate tables because one weigh-in or tape session is one dated
  entry, and the backup is generic over columns; the grouping is the UI's.
- `/planned-workouts` -- the training calendar: a routine (or free-form
  session) scheduled for a future time, with a duration and a reminder lead
  time. Deliberately **not** an activity -- activities feed every stat, so a
  plan must not count until it is performed. Starting a workout from a plan
  sends `planned_workout_id` along with `POST /activities`, which sets the
  plan's `completed_activity_id` (an unknown id is ignored rather than failing
  the save). `GET /profile/calendar`, `POST` (turn on / rotate) and `DELETE`
  manage the secret behind the ICS feed -- see "Calendar feed" below.
- `/imports/hevy/workouts` and `/imports/hevy/measurements` -- see
  "Hevy import" below.
- `/imports/intervals/preview` and `/imports/intervals/activities` -- see
  "Intervals.icu import" below.
- `GET /admin/backup` and `POST /admin/backup/restore` (admin only), and
  `GET /profile/export` and `POST /profile/import` (any user, own data only)
  -- see "Backup and data export" below.

## Retried saves

A client that finishes a workout with a flaky connection cannot tell "the
request never arrived" from "it was stored but the response was lost", so it
retries -- and without care that stores the workout twice. `POST /activities`
therefore treats a request from the same caller with the same title, start and
end as the first save replayed: it returns the existing activity (`200`
rather than `201`) instead of creating another. No idempotency-key column is
needed because a live workout's start time is a full-precision device
timestamp, so two genuinely different workouts do not collide on it. The
other half of this lives in the app, which freezes the title once an attempt
may have gone through, since the title is part of that key -- see
[Frontend](frontend.md#finishing-a-workout-without-a-connection).

Routine exercises carry a `superset_group`, as activity exercises always have:
exercises sharing a number are done back-to-back, and starting a workout from
a routine copies it over. How the groups are kept coherent is client-side, see
[Frontend](frontend.md#supersets).

## API documentation

FastAPI serves its generated schema itself -- `/docs` (Swagger UI), `/redoc`
and `/openapi.json` -- so the documentation is the routers and schemas
themselves, and can't drift from the API. `main.py` only adds a description
and `openapi_tags` on top: descriptions and the grouping in the page's tag
list are worth writing by hand, but everything else is derived.

The app shows the same page at its own `/docs` route (Profile -> "API
documentation"). On the web target that's an iframe of `<server>/docs`, so
there's one source of truth: the in-app screen decides *where* the docs
render, not *what* they say. Everywhere else -- native targets, and the web
when the browser refuses the frame -- the same screen falls back to the URLs
with a copy button, rather than showing an empty box. The frame is refused in
one case worth naming: an HTTPS page framing an HTTP backend is mixed content,
which no page is allowed to work around.

Two things about that screen are less obvious than they look:

- The route is reached with `context.go`, not `context.push`. Verified in a
  real browser: `push` renders the screen correctly but leaves the address
  bar on `#/profile`, so the `/docs` link can't be copied, bookmarked or
  reloaded -- which is the entire point of giving it its own route. `go` fixes
  the URL and leaves nothing to pop, hence the screen's own explicit back
  button. A unit test asserting the router's location would *not* have caught
  this, because the router state was correct in the failing case too; only
  the browser's address bar wasn't.
- The route lives at `/#/docs`, not `/docs`. Flutter web routes with a hash, so
  that is the real form of the URL; a bare `/docs` would be the backend's own
  page. If you serve both behind one origin, keep that distinction straight.

Swagger UI loads its own JavaScript and CSS from `cdn.jsdelivr.net`, which
`/openapi.json` does not: behind an air gap the frame renders empty and the
console says `SwaggerUIBundle is not defined`. Vendoring those assets (a
`swagger-ui-dist` copy, served by the backend) would fix it, at the cost of a
copied JS bundle and its license to keep in sync; the raw schema is the better
codegen input regardless. See
[Browsing the API documentation](../deploy/quickstart.md#browsing-the-api-documentation)
for what this means for an air-gapped deployment.

## Authentication

Multi-user accounts, not a single-instance password gate: anyone can
`POST /auth/register` unless `DINATOS_ALLOW_REGISTRATION=false` (the first
account on a fresh instance becomes admin, and can always register, so a
locked-down instance is never unbootstrappable). Admins can create accounts
regardless of that flag via `POST /admin/users` (the `/admin/*` routes sit
behind the `require_admin` dependency); `GET /auth/config` is the public
endpoint the login screen reads to decide whether to show "Register". Then `POST /auth/login` to get a
bearer token.

**This is a server-side session per login (`AuthSession`), not a
self-verifying token.** The string handed back by `/auth/login` is nothing
but a high-entropy random value (`services.auth.generate_session_token`);
only its SHA-256 hash is stored, and every authenticated request looks that
hash up to find the session it names (`services.auth.get_valid_session`). An
earlier version of this used a signed, stateless JWT instead -- verified by
signature and expiry alone, no database lookup, on the reasoning that this
is a small, self-hosted app where a per-request DB check costs nothing worth
avoiding. That was true, but it also meant there was no way to revoke a
token before it expired, and no honest way to offer `POST /auth/logout`: one
that returned success without revoking anything would be an API contract
that lies. Once every request already needs a database lookup for other
reasons, a self-verifying signed token buys nothing a plain opaque one
doesn't -- so the JWT was dropped along with the constraint that motivated
it, in favor of a real session that a real logout can end.

`POST /auth/logout` revokes **exactly the session its bearer token names**
(`AuthSession.revoked_at`), not every session the account has open --
logging out on one device or browser tab doesn't sign out others that
logged in separately. A revoked or expired session is indistinguishable from
an unknown one to every other endpoint: same `401`, same message, nothing in
the response reveals which case it was.

Sessions default to a **30-day** lifetime (`session_ttl_days`), long
compared to the earlier stateless design's 15 minutes: since a session is
now revocable, its TTL isn't the only thing standing between a leaked token
and account compromise, so it can favor not making someone re-authenticate
mid-workout over minimizing exposure window. Revocation (logout, or noticing
a device was stolen and manually deleting its `AuthSession` row) is the real
mitigation now; the TTL is a backstop for a session nobody ever explicitly
ends.

Passwords are hashed with Argon2 (`argon2-cffi`), never compared or stored
in the clear -- deliberately not a fast general-purpose hash (BLAKE3,
SHA-256, etc.): those are fast *by design*, which is exactly wrong for
password storage, since it lets anyone who steals the `users.password_hash`
column brute-force it at GPU speed. Argon2's slowness is the point. The
session token itself is hashed with plain SHA-256 instead, deliberately --
it's already 256 bits of randomness, nothing about it is brute-forceable, so
Argon2's slowness there would only cost real request latency for no
security benefit. Never swap the two: Argon2 for the password, SHA-256 for
the session token.

## Backup and data export

Two features share one idea -- a versioned JSON document with a `format`
name, a `format_version`, `exported_at` and `app_version` (`schemas/backup.py`)
-- and differ in everything else.

### Full server backup (admin only)

`GET /admin/backup` downloads every table as `{"tables": {name: [row, ...]}}`;
`POST /admin/backup/restore` (multipart `file`, plus the form field
`confirm=true` -- without it a 400, nothing read) **resets the whole server
to that document**. The mechanics are in `services/backup.py`:

- **Generic over the table metadata**: every column of every table in
  `BACKED_UP_TABLES` is exported, rows carry their original primary keys,
  enums as their value, timestamps as UTC ISO 8601. Adding a *column* needs no
  change here. Adding a *table* does: `tests/services/test_backup_coverage.py`
  fails until the table is in `BACKED_UP_TABLES` or in `EXCLUDED_TABLES` with
  a reason. A column added after a backup was made is filled from its
  nullable/default when restoring that older backup; bump `FORMAT_VERSION`
  only for a change an old reader cannot interpret (a column or table
  removed or re-meant).
- **Validate, then replace.** `parse_backup` checks the whole document
  before the database is touched: format name, version, exact table set,
  every column's presence/type/length/enum, primary-key uniqueness, every
  foreign key resolving, and at least one admin account (a backup that would
  lock everyone out is refused). Any problem is a 422 listing them. Only then
  does `restore_backup` delete every table (children first) and insert the
  document (parents first), in **one transaction**: if the database still
  rejects something (a unique constraint, say), everything rolls back and
  the server is exactly as before.
- **Postgres sequences.** Inserting explicit ids leaves each serial
  sequence behind, so the next ordinary insert would collide.
  `reset_sequences` runs a `setval(pg_get_serial_sequence(...), max(id)+1)`
  per autoincrement key -- on Postgres only (sqlite derives the next rowid
  from the table). The statements are unit-tested and the dialect switch is
  tested with a stub, but no test runs them against a real Postgres.
- **Secrets.** The backup contains password hashes and stored WorkoutX API
  keys, in the clear, because restoring must give a working server. Treat the
  file as a credential; the endpoint's docs and the app say so.
- **Sessions.** `auth_sessions` is *excluded*: a row is a live login, so
  a backup file must not carry them, and a restore must not resurrect old
  ones. After a restore every login is gone, except **the calling admin's
  own current session, which is kept iff the backup contains a user with
  the same id *and* the same email** (`session_kept` in the response). Id
  alone is not enough: on a fresh instance the backup's user 1 may be a
  different person than the caller's user 1. If it is not kept the caller
  is logged out like everyone else (their next request is a 401).

### A user's own data (`/profile/export`, `/profile/import`)

`services/user_export.py`. Not generic: it is a hand-shaped, id-free
document (`UserExport`) of the profile settings, the exercises the data
uses, routines, activities and body measurements. Never the password hash,
sessions, Hevy/Intervals.icu import records, or the WorkoutX API key (it is a credential
and stays on the server it was typed into; an import ignores one if a file
smuggles it in).

- **Exercises are global** (no owner), so "the user's custom exercises"
  means the exercises their routines/activities reference. They travel with
  their definition and are matched on import **by exact name**: an existing
  entry (built-in or custom) is reused and never modified; an unknown name
  is created as a custom exercise. Referring to an exercise the file does
  not define and the server does not have is a 422.
- **Ids are remapped.** Nothing in the file is a database id; an activity
  names the routine it ran from by `routine_ref`, its 1-based position in
  the file's `routines`.
- **Merge (default)** keeps everything already in the account and skips what
  is already present, so importing a file twice is harmless: a routine is
  present if the caller has one with the same *name*, an activity if title
  and start time match, a measurement if its timestamp matches. Presence is
  judged against the account as it was before the import (two same-named
  routines inside one file both arrive). An activity whose routine was
  skipped as present is linked to the existing routine. **Replace**
  (`?mode=replace`) first deletes the caller's routines, activities and
  measurements. Profile settings are applied in both modes.
- `DELETE /profile/data` clears the account: the caller's routines, activities,
  measurements and Hevy/Intervals.icu import records, plus every custom exercise no
  remaining routine or activity (anyone's) references -- exercises are shared,
  so one another account still uses survives. Settings and the user stay.
- Every row written has `owner_id` set to the caller; nothing else in the
  database is touched. A file is fully validated (shape by pydantic, then
  references) before the first write, and applied in one transaction.

**When you add a table or column**, update the backup: a new table goes in
`BACKED_UP_TABLES` (the coverage test makes you); a new user-owned
domain field also belongs in `schemas/backup.py`'s `Exported*` models and
`services/user_export.py` (no test can know whether a new column is
user-portable, so this one is on you -- the roundtrip tests in
`tests/api/test_user_export_roundtrip.py` compare whole documents, so extend
`tests/backup_seed.py` with a value for it).

## API keys

A person can create named API keys (`POST /api-keys`; **Settings > API keys** in
the app) for tools to act as them -- chiefly the MCP server -- instead of
handing a tool their password or a login session. A key is `dnk_` plus 32
random bytes. As with sessions, **only a SHA-256 of it is stored**
(`models/api_key.py`, `services/api_keys.py`): the create response is the one
and only time the key is shown, and what listing returns is the name, creation
and last-use times and the key's last three characters (`suffix`), enough to
tell keys apart. Deleting a key revokes it at once. `last_used_at` is refreshed
at most once a minute, so using a key is not a write on every request.

`get_current_user` (`api/deps.py`) accepts either credential: the `dnk_` prefix
selects the key lookup, anything else the session lookup. What a key
**cannot** do is anything behind `get_session_user`, which accepts a login
session only: manage keys (so a leaked key cannot mint more or hide itself),
log out, and every `/admin/*` route (so a key cannot back up or restore the
server). At most 25 keys per account.

## Calendar feed

`GET /calendar/{token}.ics` serves the caller's planned workouts as an
iCalendar document (`services/calendar.py`) that Google/Apple/Outlook calendars
subscribe to by URL. Calendar apps cannot log in, so this is the one
unauthenticated route besides `/health` and `/auth/*`: the unguessable token
(`UserProfile.calendar_token`, `secrets.token_urlsafe(32)`) in the path is the
credential. It is stored in the clear -- unlike an API key it is shown again, so
the person can re-copy their link -- and so is excluded from the per-user export
but, like every profile column, part of the admin backup. `POST /profile/calendar`
rotates it (the old link then 404s), `DELETE` turns the feed off.

The document is generated from the database on every request, so it is never
stale; "updating periodically" is the subscriber re-fetching, which the feed asks
for hourly (`REFRESH-INTERVAL` / `X-PUBLISHED-TTL`; Google Calendar polls only
every several hours regardless). Events carry a stable `UID` (`planned-<id>@dinatos`)
and a `SEQUENCE` taken from `updated_at`, so an edit updates the event instead of
duplicating it, plus a `VALARM` from the reminder lead time. The feed covers the
last 90 days onward. The client builds the full URL from its own server address
(`<server>/calendar/<token>.ics`): only it knows how the server is reached.

## MCP server

The API hosts an MCP server itself, at `/mcp` (streamable HTTP, `api/mcp.py`),
so an MCP client needs only the server's URL and an API key -- nothing to
install. It is stateless (the key travels with every request), which lets it sit
behind any proxy. `McpGateway` authenticates each request -- only `dnk_` API
keys, checked against the database up front so a bad key fails at connection
time -- and each tool then calls the ordinary REST API **in-process** with that
same key over an ASGI transport. The MCP therefore does exactly what the app can
for that person, with the same validation and ownership rules, and no second set
of business logic to keep in step. Its transport is started and stopped by the
app's lifespan (`McpGateway.running()`); a fresh one is built each time, so tests
can start it per test.

The tools are plain wrappers over endpoints (exercises, routines, activities)
the calendar (`list_planned_workouts`, `schedule_workout`,
`update_planned_workout` -- a `PATCH`, so only the arguments passed change --
and `delete_planned_workout`), plus `get_persona_stats`, which runs `services/personas.py`: a Python port of
the app's on-device persona scoring (`frontend/lib/features/personas/`). The two
implementations are kept honest by a shared fixture
(`frontend/test/fixtures/persona_parity.json`) that both test suites run -- change
the scoring in one and the other's test fails until it matches.

`mcp_server/` (package `dinatos-mcp`, entry point `dinatos-mcp`) is a small stdio
**proxy** to that endpoint, for clients that can only launch a local program. It
defines no tools: it lists and calls whatever the server offers, so the two can
never disagree. It is configured with `DINATOS_MCP_BASE_URL` and
`DINATOS_MCP_API_KEY` only -- API-key auth is the single way in; there is no
email/password or session-token option. It is still its own `uv` project and
depends on `dinatos_backend` only in its tests, which run it against the real
app in-process. `docs/user-guide/mcp-server.md` covers pointing a harness at
either.

## Hevy import

`POST /imports/hevy/workouts` and `POST /imports/hevy/measurements` take
Hevy's own CSV exports (Settings -> Export in the Hevy app) as a multipart
file upload. The workout export is one row per set, grouped back into
activities by `(title, start_time, end_time)`, and into exercise instances
by watching `set_index` reset to `0`. See
`backend/src/dinatos_backend/services/hevy_import.py` for exactly how, and
`backend/tests/fixtures/hevy_*.csv` for synthetic sample files covering
warmups/dropsets/supersets/bodyweight/cardio -- fixtures are synthetic
rather than a real export on purpose, so nobody's actual training history
ends up committed to a public repo. Each fixture set exists in both of the
two timestamp flavours Hevy emits, depending on which app exported it: the
Android export writes `1 Jan 2026, 08:00` (day-first, 24-hour) and the
web/PC export writes `Jan 1, 2026, 8:00 AM` (month-first, 12-hour), so
`_parse_timestamp` accepts either and the behavioural tests are parametrized
over both. The importer was also verified once,
locally, against a real account export (75 activities, 468 exercise
instances, 1148 sets, 131 exercises, 3 measurements -- all matching the
source file's row counts exactly); that data was never committed.

This is a one-shot migration path, not an ongoing sync. Re-importing the
exact same file content (by SHA-256, not filename -- Hevy names every export
the same thing) is rejected with `409 Conflict`, naming when the earlier
import ran and what filename it was uploaded as, rather than silently
creating duplicate activities. Pass `?force=true` to import it again anyway.
Every import that actually runs (first time or forced) is logged as a
`HevyImportRecord`; a different file -- one byte changed, one new workout
added in Hevy since the last export -- is not a duplicate and imports
normally.

The profile screen's "Import from Hevy" entry (`frontend/lib/features/
imports/`) drives this from the app itself -- see
[Importing from Hevy](../user-guide/hevy-import.md) for that flow from a
user's side. A `409` surfaces as a dialog naming the previous import's
filename/timestamp and asking to confirm before retrying with `?force=true`
-- `HevyImportRepository` is what turns that one status code into a typed
`HevyImportAlreadyDoneException` instead of a generic error.

### Guessing metadata for created exercises

Hevy's CSV has only an exercise *title* -- no equipment, no muscles. A title
that matches nothing in the seeded catalog (`hevy_exercise_match`) becomes a
custom exercise, and `services/hevy_exercise_infer.py` guesses its metadata,
deterministically and without any network/LLM call:

- **Equipment** from Hevy's parenthesised suffix ("Row (Dumbbell)"), mapped
  onto the `Equipment` enum; an unknown suffix is ignored and equipment words
  in the name ("Dumbbell Row") are the fallback.
- **Muscles** from the seeded catalog's most similar exercises: names are
  compared as word sets with equipment/filler words stripped (Dice
  coefficient, threshold 0.6), and up to three close neighbours vote,
  weighted by similarity. If no neighbour qualifies, a small ordered
  movement-keyword table (row -> back, curl -> biceps, ...) is tried; if
  that finds nothing either, the muscles stay empty rather than wrong.

Only seeded exercises are ever neighbours -- never a person's own, or earlier
guesses -- so a result doesn't depend on what else was imported. The guesses
are saved on the new exercise and the workouts response lists every created
exercise in `created_exercises` with `equipment_guessed`/`muscles_guessed`
flags; the import screen turns that into a "please review these" card linking
to each exercise's edit screen. Re-importing creates nothing (and so reports
nothing): existing exercises, including ones the person has since edited, are
never re-inferred.

## Intervals.icu import

A one-time import of chosen [Intervals.icu](https://intervals.icu) activities,
for someone who also tracks there. It is the sibling of the Hevy import above
-- a one-shot migration, not a sync; nothing runs in the background -- but its
source is an API rather than a file, which changes how a second run is made
safe. Code: `services/intervals_client.py` (the HTTP side),
`services/intervals_import.py` (mapping, selection, duplicate handling),
`api/routers/intervals_imports.py`, and `models/intervals_import.py`.

**Two steps, both `POST`.** `POST /imports/intervals/preview` fetches the
activities in a date window (`oldest`, `newest` defaulting to today) and
returns them annotated, writing nothing. `POST /imports/intervals/activities`
takes the same window plus `activity_ids` -- the person's selection -- and
imports exactly those. The import re-fetches the window rather than trusting
activity data sent back by the client, so what is written is always what
Intervals.icu says; an id missing from that window, or unimportable, is a `422`
and nothing is written. Both are `POST` because the **API key travels in the
body**: it is used for that request and never stored (no profile column, not in
a backup or export, never echoed -- there is a test for the last). That also
means there is no WorkoutX-style `UserProfile` field to keep out of exports.
The athlete id is validated against `^(0|i?\d+)$` because it becomes a URL
path segment, and the base URL is a constant, so the endpoint cannot be pointed
at another host. A key Intervals.icu rejects is a `400`, deliberately **not**
`401`: the app logs the person out on a 401 from this API, and this is not
their Dinatos session. Intervals.icu being down is a `502`.

**Mapping.** Each activity becomes one `Activity` (title from its name, start
from `start_date_local`, end from the elapsed time) with one exercise named for
its sport -- `Run` -> "Running" and so on through a small table, otherwise the
type split on its capitals -- holding one set with the moving time and the
distance. An exercise of that exact name is reused; otherwise a custom one is
created tracking duration (and distance if any selected activity had it).
Intervals.icu has no per-exercise strength data, so a `WeightTraining` activity
is just a timed entry. Timestamps are stored as the naive wall-clock time, the
same as Hevy's CSV timestamps. Strava-sourced activities come back from
Intervals.icu as a stub (an `id` and a `_note`); they are listed as
unimportable rather than dropped, so the person sees why they are missing.

**Second runs are safe per activity, not per file.** A Hevy export has no ids,
so duplicates are caught by hashing the whole file (`HevyImportRecord`).
An Intervals.icu activity has a stable id, so each import is recorded per
activity in `IntervalsImportedActivity` -- unique on `(owner_id, intervals_id)`,
pointing at the `Activity` it created -- and the same activity is never
imported twice by default, including across overlapping date ranges, which a
file hash could not catch. The behaviour deliberately mirrors the Hevy one:

- a request that includes an activity already imported is rejected whole with
  `409` -- nothing written, not a partial import -- naming those ids and when
  they were imported; `?force=true` imports them again anyway, creating a
  second `Activity` and repointing the existing record at it rather than adding
  a second record;
- duplicates are scoped per `owner_id`;
- the whole selection is written in one transaction. Two requests importing the
  same activity at once cannot both win: the unique constraint makes the loser
  fail at commit, which is rolled back and reported as the same `409`;
- a record only counts while the `Activity` it points at still exists (the
  lookup joins to it -- sqlite, which the tests run on, has no cascade to rely
  on, and Postgres' `ON DELETE CASCADE` is just belt and braces), so deleting
  an imported activity makes it importable again without `force`. For the same
  reason the records are deleted with the activities in `replace` and in
  `DELETE /profile/data`.

**Duplicates with Hevy.** Hevy can sync to Intervals.icu, so the same workout
may already be in Dinatos. The preview flags (`possible_duplicate_of`, the title
found) any activity starting within 30 minutes of an existing one of the same
owner (`DUPLICATE_WINDOW`) and the app leaves it unticked. It is advisory only:
the backend never skips a selected activity for that reason, because only the
person knows whether it is really the same session.

The records table is in `BACKED_UP_TABLES` (a full server backup restores it
with its `activities` foreign keys) but not in the per-user export, like the
Hevy records. The app side is `frontend/lib/features/imports/intervals_import_*`
(Profile -> Import from Intervals.icu): the list defaults to ticking only what
is importable, not already imported and not a possible duplicate, remembers the
key and window the list was fetched with so later edits to the form do not leak
into the import, and turns the `409` into the same "import again anyway?"
dialog as the Hevy screen (`IntervalsAlreadyImportedException`). The tests fake
Intervals.icu with an `httpx2.MockTransport` injected through the
`get_intervals_client` dependency; no test touches the network.

## Exercise tutorials

`GET /exercises/{id}/tutorial` returns a GIF plus instructions/muscles/
equipment for an exercise, from whichever provider is active:

- **`free-exercise-db`** (the default, needs nothing configured) -- a
  vendored, public-domain dataset from
  [yuhonas/free-exercise-db](https://github.com/yuhonas/free-exercise-db)
  (`backend/src/dinatos_backend/data/free_exercise_db.json`, see that
  directory's `NOTICE.md` for provenance/license). It's also what
  `services.exercise.bootstrap_default_exercises` seeds a brand new
  instance's `exercises` table from, so an instance's exercise names match
  this dataset's own exactly -- a tutorial lookup by name always hits, no
  fuzzy matching needed.
- **[WorkoutX](https://workoutxapp.com)**, opt-in per user -- each user can
  save their own API key in the app's Settings screen (`PATCH /profile`,
  stored in `user_profile.workoutx_api_key`) to get real animated GIFs
  rather than free-exercise-db's two static JPGs per exercise. There is
  deliberately no instance-wide key: this project never holds a shared one,
  and one user's lookups are never served from, or billed to, another's
  WorkoutX account. The key is stored as-is (it must be sent to WorkoutX on every lookup, so a hash
  would be useless) and is write-only over the API: `GET /profile` only
  reports `has_workoutx_api_key`.

WorkoutX's GIF URLs (`/v1/gifs/<id>.gif`) answer 401 without the key too,
and a browser `<img>` / Flutter `Image.network` cannot send the
`X-WorkoutX-Key` header (nor should the key ride in a URL query string, where
it would leak to the client and logs). So the provider rewrites each GIF URL
to `/exercises/media/workoutx/<id>.gif`, an authenticated backend endpoint
that fetches the GIF with the caller's own saved key and streams the bytes
back; the app fetches it through its normal bearer-token Dio client.

Both providers implement the same `TutorialProvider` protocol
(`backend/src/dinatos_backend/services/tutorials/base.py`), so adding a
third is a new adapter, not a rewrite;
`services.tutorials.get_tutorial_provider_for_key` picks one per request:
WorkoutX for a user who saved a key (one cached provider per distinct key),
the bundled dataset otherwise. WorkoutX is wrapped in a
`FallbackTutorialProvider` (`services/tutorials/fallback.py`): if it fails
(a bad or expired key, a quota error, an outage) or has no match for an
exercise, the bundled free-exercise-db answers instead, so opting in can't
leave exercises without a tutorial. The failure is logged as a warning on
the server. The tutorial response's `source` field says which provider
answered, and the app shows it under the images with a "?" tooltip.

Every lookup is wrapped in an in-memory cache
(`services/tutorials/cache.py`) that lives only for the process's lifetime
-- deliberately never persisted to the database. Two reasons: WorkoutX's own
terms of service prohibit bulk-caching or scraping its data, so tutorials
are fetched one exercise at a time, only the moment someone actually opens
it, never a sync of the whole catalog; and this project chose not to take on
a persistent-cache schema (staleness, reconciliation, licensing implications
of storing someone else's data) for what a restart re-fetching lazily
already solves well enough. A restart pays for the first view of each
exercise again; every view after that, in the same process, doesn't.

## Container image

The root `Dockerfile` (build context: the repo root, since it needs
`frontend/` too) is a three-stage build: a `frontend-builder` stage
downloads Flutter's current `stable` release and runs `flutter build web
--release`, alongside the backend's own two-stage `uv` build (resolve +
compile in one image, ship only the venv in a slim runtime image). The
runtime stage copies in both: the venv from the backend `builder` stage, and
`build/web` from `frontend-builder` at exactly the path `Settings.web_dir`
defaults to (`web/`, under `/app`) -- see "Serving the bundled web app"
below. It all runs as a non-root numeric uid, with migrations run
automatically on start (`docker-entrypoint.sh`: `alembic upgrade head` then
`exec uvicorn ...`, so uvicorn is PID 1 and shuts down cleanly on
`SIGTERM`).

`frontend-builder` pins no Flutter version, deliberately: nothing else in
this repo does either (every CI job and the release workflow's Android/Linux
jobs use `subosito/flutter-action@v2` with `channel: stable`, no
`flutter-version:`), so a pinned archive here would just be a second,
easily-drifting source of truth for the same thing. It instead asks Google's
own `releases_linux.json` feed which archive `stable` currently points to
and downloads exactly that, right before using it -- the same approach
AGENTS.md recommends for a fresh unattended container, just resolved inside
the build itself instead of by hand.

### Serving the bundled web app

`main.py`'s `_mount_web_ui` mounts a small `StaticFiles` subclass
(`_WebApp`) at `/`, but only if `Settings.web_dir` (default: `web`, relative
to the working directory) actually exists -- true for the Docker image
(which copies the Flutter build there), false everywhere else this backend
runs (`just backend run`, every test in `backend/tests/`), where the app
behaves exactly as it did before this existed. It's mounted last, after
every API router and `/health`, so those are always matched first; `_WebApp`
only ever serves what nothing else claimed. `_WebApp.get_response` falls
back to `index.html` for anything that 404s, which in practice only matters
for a direct request to a path that isn't a real asset -- Flutter web's
default hash-based routing (`/#/routines/1`) never sends its client-side
route to the server at all, so a browser only ever requests `/` to begin
with.

The web build itself needs no `--dart-define=API_BASE_URL` at build time:
the frontend's `ApiConfig` already defaults an override-less web build to
whatever origin actually served it, which is this same backend, on the same
origin, once `_WebApp` is serving it -- see
[Clients](../deploy/clients.md) for building against a separately-hosted
backend instead.

The runtime stage's `uv sync` needs `--no-editable`: `uv sync`'s default
install of the project itself is *editable* -- a path reference back to
`/app/src` in the builder stage's filesystem, not a real package -- so
without `--no-editable` on the final `uv sync --locked --no-dev`, the
runtime image's venv points at a directory that doesn't exist there, and
every import of `dinatos_backend` fails with `ModuleNotFoundError` at
container start. This is only caught by actually running the built image
against a real Postgres, not by `docker build` succeeding -- a broken
editable install still builds fine; it only fails when something tries to
`import dinatos_backend`.

`docker-compose.yml` at the repo root wires the image up with Postgres; see
[Deploying with Docker Compose](../deploy/quickstart.md) for running it.
`just docker debug` attaches
[`nicolaka/netshoot`](https://github.com/nicolaka/netshoot) (ping,
traceroute, dig, tcpdump, curl, ...) to the running app container's network
namespace for troubleshooting -- deliberately not baked into the `Dockerfile`
itself: the runtime image never gains these tools or the layer weight of
installing them, and it's pulled from Docker Hub the first time it's used,
not part of any build.
