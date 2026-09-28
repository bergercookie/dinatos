# Backend

FastAPI + async SQLAlchemy + pydantic, backed by Postgres.

## API surface

`GET /health` and `/auth/*` aside, every endpoint requires a bearer token
(`Authorization: Bearer <token>`, from `/auth/login`) and only ever sees the
calling user's own data:

- `/auth/register`, `/auth/login`, `/auth/me`, `/auth/logout` -- see
  "Authentication" below.
- `/exercises` -- full CRUD, plus `?search=` (backs the watch-sync picker).
  The one shared, global resource: every user's catalog is the same.
  `/exercises/{id}/tutorial` -- a GIF plus instructions/muscles/equipment,
  see "Exercise tutorials" below.
- `/workouts` -- saved routine templates, scoped to their owner. Nested
  exercises/sets are created and replaced as a whole (`POST`, `PUT`); there
  is no endpoint for patching one set in isolation.
- `/activities` -- performed sessions, scoped to their owner, the same
  nested create/replace shape as workouts, plus `?since=`/`?until=`
  filtering. An activity may reference one of the caller's own `/workouts`
  templates; referencing someone else's is a 404, the same as trying to
  read it directly.
- `/profile` -- one row per user (`GET`/`PATCH`, no id in the path: always
  the caller's own).
- `/measurements` -- dated body-measurement entries, scoped to their owner.
- `/imports/hevy/workouts` and `/imports/hevy/measurements` -- see
  "Hevy import" below.

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
`POST /auth/register` (the first account on a fresh instance becomes admin;
nothing beyond that is admin-gated yet), then `POST /auth/login` to get a
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
- **[WorkoutX](https://workoutxapp.com)**, opt-in -- set
  `DINATOS_WORKOUTX_API_KEY` (see
  [Configuration reference](../deploy/configuration.md)) to use it instead,
  for real animated GIFs rather than free-exercise-db's two static JPGs per
  exercise. Each instance brings its own account/quota; this project never
  holds a shared key.

Both providers implement the same `TutorialProvider` protocol
(`backend/src/dinatos_backend/services/tutorials/base.py`), so adding a
third is a new adapter, not a rewrite;
`services.tutorials.get_tutorial_provider` picks one based on whether
`workoutx_api_key` is set.

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

`backend/Dockerfile` is a two-stage `uv` build (resolve + compile in one
image, ship only the venv in a slim runtime image), running as a non-root
numeric uid, with migrations run automatically on start
(`docker-entrypoint.sh`: `alembic upgrade head` then `exec uvicorn ...`, so
uvicorn is PID 1 and shuts down cleanly on `SIGTERM`).

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
traceroute, dig, tcpdump, curl, ...) to the running backend container's
network namespace for troubleshooting -- deliberately not baked into
`backend/Dockerfile` itself: the runtime image never gains these tools or
the layer weight of installing them, and it's pulled from Docker Hub the
first time it's used, not part of any build.
