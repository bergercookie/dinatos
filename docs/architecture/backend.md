# Backend

FastAPI + async SQLAlchemy + pydantic, backed by Postgres.

## API surface

`GET /health` and `/auth/*` aside, every endpoint requires a bearer token
(`Authorization: Bearer <token>`, from `/auth/login`) and only ever sees the
calling user's own data:

- `/auth/register`, `/auth/login`, `/auth/me`, `/auth/logout` -- see
  "Authentication" below.
- `/exercises` -- full CRUD, plus `?search=` (backs the watch-sync picker).
  The one shared, global resource: every user's catalog is the same. `PATCH`
  and `DELETE` are a 403 against a built-in (`is_custom=False`) exercise --
  only a user-created one can be edited or deleted; see "Exercise
  tutorials" below and `Exercise.is_custom`'s docstring.
  `/exercises/{id}/tutorial` -- a GIF plus instructions/muscles/equipment,
  see "Exercise tutorials" below.
- `/routines` -- saved routine templates, scoped to their owner. Nested
  exercises/sets are created and replaced as a whole (`POST`, `PUT`); there
  is no endpoint for patching one set in isolation.
- `/activities` -- performed sessions, scoped to their owner, the same
  nested create/replace shape as routines, plus `?since=`/`?until=`
  filtering. An activity may reference one of the caller's own `/routines`
  templates; referencing someone else's is a 404, the same as trying to
  read it directly.
- `/profile` -- one row per user (`GET`/`PATCH`, no id in the path: always
  the caller's own).
- `/measurements` -- dated body-measurement entries, scoped to their owner.
- `/imports/hevy/workouts` and `/imports/hevy/measurements` -- see
  "Hevy import" below.
- `GET /admin/backup` and `POST /admin/backup/restore` (admin only), and
  `GET /profile/export` and `POST /profile/import` (any user, own data only)
  -- see "Backup and data export" below.

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
sessions, Hevy import records, or the WorkoutX API key (it is a credential
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
  measurements and Hevy import records, plus every custom exercise no
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

## MCP server

`mcp_server/` (package `dinatos-mcp`, entry point `dinatos-mcp`) exposes a
handful of the endpoints above -- exercises, routines, activities -- as MCP
tools, so an LLM harness (Claude Desktop, or any other MCP client) can
create exercises, build routine templates and log activities on someone's
behalf. It's deliberately its own `uv` project (own `pyproject.toml`,
`uv.lock`, virtualenv), not a module inside `dinatos_backend`: it's a
*client* of this API, the same as the Flutter app or a `curl` script, so it
depends on this package only in its own tests (to spin up the real FastAPI
app in-process over an ASGI transport, rather than a live server) -- never
at runtime, where it talks HTTP like anyone else.

Authentication reuses the session mechanism above unchanged: `DinatosClient`
(`mcp_server/src/dinatos_mcp/client.py`) either carries a bearer token given
directly (`DINATOS_MCP_TOKEN`), or logs in lazily on first use with an email
and password (`DINATOS_MCP_EMAIL`/`DINATOS_MCP_PASSWORD`) and caches the
token it gets back for the process's lifetime -- there's no separate
service-account concept, no API key scheme of its own to maintain. See
`docs/user-guide/mcp-server.md` for how to point an LLM harness at it.

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
