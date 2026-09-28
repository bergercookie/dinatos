# Architecture

## Concepts

- **users** -- local accounts, first-class from the start: this is a
  household app, not a single-user one. `exercises` are the one thing
  shared across every account; everything else belongs to exactly one.
- **exercises** -- e.g. Romanian deadlift.
- **workouts** -- a named list of exercises, e.g. an upper-body routine.
- **activities** -- a recorded gym session: a list of completed exercises with
  their sets, reps and weights. An activity can come from running a saved
  workout, or from an ephemeral one built on the spot.

## Repository layout

```
dinatos/
  backend/   FastAPI + async SQLAlchemy + pydantic API, backed by Postgres
  frontend/  Flutter app (web today; the same codebase targets Android)
  watch/     Garmin Connect IQ (Monkey C) app
  bridge/    Sync service between the backend and the watch
  docs/      This site (Markdown, rendered with Sphinx + MyST)
```

`backend/`, `docs/` and `frontend/` exist so far; `watch/` and `bridge/` are
still ahead. Each package directory owns a plain, self-sufficient `justfile`
(runnable directly with `cd backend && just test`); the root `justfile`
imports each one as a module with `mod`, so `just backend test` works from
anywhere in the repo too.

## Build order

The parts don't get built in parallel: the watch app would just end up
chasing a domain model that is still moving. Instead:

1. **Tooling skeleton** -- justfiles, pre-commit (ruff, mypy, tach, pytest),
   an empty FastAPI app with a health check, CI running `just check`. *(done)*
2. **Backend core** -- exercises, workouts, activities and settings: full
   CRUD over Postgres via async SQLAlchemy, with the test suite as the spec.
   *(done: see "API surface" below)*
3. **Hevy import** -- backend-only work that stress-tests the schema against
   real exported data before anything else depends on it. *(done, verified
   against a real export -- see "Hevy import" below)*
4. **Flutter frontend** against the now-stable API -- this is where the
   domain model actually gets validated, before investing in watch sync.
   *(done: exercises, workouts, activities, profile and measurements all
   have working screens against the real API -- see "Frontend" below)*
   *(current stage)*
5. **Garmin bridge + watch app** -- a small relay service the watch polls,
   plus the Connect IQ app itself.

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
- `/imports/hevy/workouts` and `/imports/hevy/measurements` -- see below.

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
codegen input regardless.

## Authentication

Multi-user accounts, not a single-instance password gate: anyone can
`POST /auth/register` (the first account on a fresh instance becomes admin;
nothing beyond that is admin-gated yet), then `POST /auth/login` to get a
bearer token.

**This is a server-side session per login (`AuthSession`), not a
self-verifying token.** The string handed back by `/auth/login` is nothing
but a high-entropy random value (`services.auth.generate_session_token`);
only its SHA-256 hash is stored, and every authenticated request looks that
hash up to find the session it names (`services.auth.get_valid_session`).
An earlier version of this used a signed, stateless JWT instead -- verified
by signature and expiry alone, no database lookup, on the reasoning that
this is a small, self-hosted app where a per-request DB check costs
nothing worth avoiding. That was true, but it also meant there was no way
to revoke a token before it expired, and no honest way to offer
`POST /auth/logout`: one that returned success without revoking anything
would be an API contract that lies. Once every request already needs a
database lookup for other reasons (see below), a self-verifying signed
token buys nothing a plain opaque one doesn't -- so the JWT was dropped
along with the constraint that motivated it, in favor of a real session
that a real logout can end.

`POST /auth/logout` revokes **exactly the session its bearer token names**
(`AuthSession.revoked_at`), not every session the account has open --
logging out on one device or browser tab doesn't sign out others that
logged in separately. A revoked or expired session is indistinguishable
from an unknown one to every other endpoint: same `401`, same message,
nothing in the response reveals which case it was.

Sessions default to a **30-day** lifetime (`session_ttl_days`), long
compared to the earlier stateless design's 15 minutes: since a session is
now revocable, its TTL isn't the only thing standing between a leaked
token and account compromise, so it can favor not making someone
re-authenticate mid-workout over minimizing exposure window. Revocation
(logout, or noticing a device was stolen and manually deleting its
`AuthSession` row) is the real mitigation now; the TTL is a backstop for
a session nobody ever explicitly ends.

Passwords are hashed with Argon2 (`argon2-cffi`), never compared or stored
in the clear -- deliberately not a fast general-purpose hash (BLAKE3,
SHA-256, etc.): those are fast *by design*, which is exactly wrong for
password storage, since it lets anyone who steals the `users.password_hash`
column brute-force it at GPU speed. Argon2's slowness is the point. The
session token itself is hashed with plain SHA-256 instead, deliberately --
it's already 256 bits of randomness, nothing about it is brute-forceable,
so Argon2's slowness there would only cost real request latency for no
security benefit. Never swap the two: Argon2 for the password, SHA-256 for
the session token.

## Hevy import

`POST /imports/hevy/workouts` and `POST /imports/hevy/measurements` take
Hevy's own CSV exports (Settings -> Export in the Hevy app) as a multipart
file upload. The workout export is one row per set, grouped back into
activities by `(title, start_time, end_time)`, and into exercise instances by
watching `set_index` reset to `0`. See
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
imports/`) drives this from the app itself, rather than needing `curl`: a
native file picker (`file_picker`) for each CSV, uploaded as multipart form
data. A `409` surfaces as a dialog naming the previous import's filename/
timestamp and asking to confirm before retrying with `?force=true` --
`HevyImportRepository` is what turns that one status code into a typed
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
  instance's `exercises` table from (see "Getting started"), so an
  instance's exercise names match this dataset's own exactly -- a
  tutorial lookup by name always hits, no fuzzy matching needed.
- **[WorkoutX](https://workoutxapp.com)**, opt-in -- set
  `DINATOS_WORKOUTX_API_KEY` to a homelab admin's own account's API key
  (see `.env.example`) to use it instead, for real animated GIFs rather
  than free-exercise-db's two static JPGs per exercise. Each instance
  brings its own account/quota; this project never holds a shared key.

Both providers implement the same `TutorialProvider` protocol
(`backend/src/dinatos_backend/services/tutorials/base.py`), so adding a
third is a new adapter, not a rewrite; `services.tutorials.get_tutorial_provider`
picks one based on whether `workoutx_api_key` is set.

Every lookup is wrapped in an in-memory cache
(`services/tutorials/cache.py`) that lives only for the process's
lifetime -- deliberately never persisted to the database. Two reasons:
WorkoutX's own terms of service prohibit bulk-caching or scraping its
data ("Scrape or cache exercise data in bulk beyond what is needed for
your application"), so tutorials are fetched one exercise at a time, only
the moment someone actually opens it, never a sync of the whole catalog;
and this project chose not to take on a persistent-cache schema (staleness,
reconciliation, licensing implications of storing someone else's data) for
what a restart re-fetching lazily already solves well enough. A restart
pays for the first view of each exercise again; every view after that, in
the same process, doesn't.

## Testing migrations

`just backend test-migrations` (`backend/tests_migrations/`) runs
[pytest-alembic](https://pytest-alembic.readthedocs.io/)'s built-in suite
against a real, throwaway Postgres started by `testcontainers`: single head
revision, a clean upgrade, models matching the migrations' DDL, and every
migration upgraded and downgraded individually -- not just the head<->base
jump. It needs Docker and takes real seconds, so it runs as its own CI job
rather than as part of `just check`. See `AGENTS.md` for why it exists: a
Postgres-specific bug (an ENUM type left behind by `downgrade()`, breaking
the next `upgrade()`) is exactly the kind of thing a sqlite-backed test
suite structurally cannot catch.

Alembic's own configuration (`script_location`, etc.) lives in
`backend/pyproject.toml`'s `[tool.alembic]` rather than `alembic.ini`, which
now holds only the logging setup `env.py`'s `fileConfig()` call needs (the
one piece with no TOML equivalent). See `AGENTS.md` for the one rule that
matters here: never set the same key in both places.

## Container image

`backend/Dockerfile` is a two-stage `uv` build (resolve + compile in one
image, ship only the venv in a slim runtime image), running as a non-root
numeric uid, with migrations run automatically on start
(`docker-entrypoint.sh`: `alembic upgrade head` then `exec uvicorn ...`, so
uvicorn is PID 1 and shuts down cleanly on `SIGTERM`). `docker-compose.yml`
at the repo root wires it up with Postgres; `just docker build`/`up`/`logs`/
`down` (root `justfile`, the `docker` module) drive it. See AGENTS.md for
the one non-obvious failure mode (`--no-editable` on the build's second
`uv sync`) and why it only shows up when the built image actually runs, not
when it merely builds.

`hadolint` lints the Dockerfile as a pre-commit hook (`AleksaC/hadolint-py`
-- a pinned wheel of the prebuilt binary, not a Python dependency of the
backend itself, so it's a pinned external repo like
`pre-commit/pre-commit-hooks` rather than a `local` hook run through `uv`).

`just docker debug` attaches [`nicolaka/netshoot`](https://github.com/nicolaka/netshoot)
(ping, traceroute, dig, tcpdump, curl, ...) to the running backend
container's network namespace for troubleshooting -- deliberately not baked
into `backend/Dockerfile` itself: the runtime image never gains these tools
or the layer weight of installing them, there's no curated tool list to keep
in sync with the Dockerfile over time, and netshoot's toolbox is broader
than anything worth hand-picking. It's pulled from Docker Hub the first time
it's used, not part of any build.

## Frontend

`frontend/` is a Flutter app (web, Android, and Linux desktop -- see
"Distribution" below for how each one ships) against the backend's REST
API, with no code generation step (no
`build_runner`, no `freezed`) -- models are hand-written classes with
`fromJson`/`toJson`, and state management is plain Riverpod (`Provider`,
`StateNotifierProvider`, `FutureProvider`), not the `@riverpod`-annotated
generator variant. One dependency less to keep in sync, and nothing to
regenerate when a model's shape changes.

Layout:

```
frontend/lib/
  core/       API client (Dio + an auth interceptor), auth state/storage,
              routing (go_router), theme
  models/     Hand-written request/response types, one file per resource
  features/   One directory per resource (exercises, workouts, activities,
              profile, measurements, auth, home) -- each with its own
              repository (wraps Dio), Riverpod providers, and screens
```

Auth mirrors the backend's design deliberately: the session token is
persisted (`flutter_secure_storage`, not a cookie), there is no refresh
token, and a 401 from *any* request (caught by a Dio interceptor) clears it
and routes back to `/login` -- there is nothing to refresh, so a 401 always
means "log in again," never "retry after refreshing." `go_router` redirects
based on that auth state, not on which screen thinks it's logged in.
Logging out (the profile screen's app bar icon) calls `POST /auth/logout`
to revoke the session server-side, then clears the local token regardless of
whether that call succeeded -- if the backend is unreachable, "logged out on
this device" still has to win over leaving the person stuck signed in.

The backend's base URL is persisted too (a separate key from the session
token -- see `core/server_url_provider.dart`), not just baked in at compile
time via `--dart-define=API_BASE_URL`: a binary built once by the release
workflow and handed to someone else is only useful if it can point at
*their* own backend, not whichever one built it. It's editable from the
login screen (before ever signing in -- committed just before the actual
login/register call, so that call always goes to whatever the field
currently says) and from the profile screen (which logs out first, since a
session token from one backend is meaningless on another). Every state
transition in `AuthNotifier._bootstrap` is guarded by `state is
AuthUnknown`: changing the server URL rebuilds `AuthNotifier` (it watches
`dioProvider`, which watches the server URL) at the same moment a
login/logout call may already be in flight on the fresh instance, and
without the guard whichever finished last would silently win.

`flutter_secure_storage`'s Linux backend is the system keyring (libsecret);
one that isn't running or unlocked -- common outside a full GNOME/KDE
session, and the reason the release workflow's Linux job installs
`libsecret-1-dev` to *build* against, not just to have present at runtime --
makes every call throw `PlatformException` instead of returning null.
`TokenStorage`/`ServerUrlStorage` both catch that at every call site and
treat it as "nothing stored"/"couldn't persist": the alternative, letting
it propagate out of `main()`'s startup read, crashed the app before it ever
showed a window. Both classes (and the later `InsecureTlsStorage`) depend
on a small `SecureStore` interface (`core/secure_store.dart`) rather than
`FlutterSecureStorage` directly, specifically so a fake can stand in for it
under `flutter test`, which has no platform channel at all.

Next to the server URL, on the same two screens, is a per-server toggle to
skip TLS certificate verification (`core/insecure_tls_provider.dart`,
wired into `dioProvider` via `core/insecure_tls_configurator.dart`) -- for
a homelab server sitting behind a reverse proxy with a self-signed
certificate, which otherwise can't be reached at all short of installing a
CA on every device. Off by default: it's a real reduction in security (any
network path can then impersonate the server), not just a convenience, so
it's opt-in rather than something CORS-style middleware could paper over.
It only does anything on Android and Linux desktop -- the web target
can't touch the browser's own TLS handshake from Dart at all, so
`insecure_tls_configurator_stub.dart` (picked via `dart.library.io`
conditional export) is a deliberate no-op there.

`workouts` and `activities` share the same nested "exercises, each with
sets" editing shape the backend's schemas do (see "API surface"), including
the same full-replace semantics on save (`PUT`, not per-set `PATCH`). An
activity's "start from a saved workout" button copies a workout's exercises
and target weights/reps into a new activity client-side -- convenience only,
not an API relationship beyond the `workout_id` reference already stored on
the created activity.

The web target needs the backend's CORS middleware (`cors_allowed_origins`
in `backend/src/dinatos_backend/config.py`, wired up in `main.py`): a
browser enforces CORS on cross-origin requests, and the frontend's origin
(whatever serves the Flutter web build) is never the backend's own. Native
targets (Android) don't go through a browser and aren't affected either way.
This was found, not assumed -- by actually running the built web app in a
browser against a live backend, which is what surfaced the missing
middleware as a `net::ERR_FAILED`/"could not reach the server" in the first
place; `flutter analyze`/`flutter test` have no way to catch a CORS problem,
since there's no browser involved in either.

The `/docs` route is the other browser-only problem here, and it needed a
browser to find for the same reason -- see "API documentation" above.

## Distribution

Pushing a `v*` tag (e.g. `v1.2.3`) runs `.github/workflows/release.yml`,
which builds and publishes, in parallel, everything a release needs:

- The backend, as a Docker image pushed to
  `ghcr.io/<owner>/dinatos-backend`, tagged with the version and `latest`
  (`linux/amd64` only -- see the workflow's own comment on what adding
  `linux/arm64` would need).
- The Linux desktop client, packaged both as a `.deb`
  (`packaging/linux/build-deb.sh`) and a portable `.AppImage`
  (`packaging/linux/build-appimage.sh`) -- both from the same
  `flutter build linux --release` bundle, so the two scripts can't drift
  apart on what they're packaging.
- An Android APK, debug-signed: `android/app/build.gradle.kts`'s release
  build type still points at the debug signing config, deliberately, since
  a real release keystore is future work (see AGENTS.md), not a gap in the
  workflow itself.

The same artifacts can be produced locally from the repository root with
`just packaging build-apk <version> [build-number]`,
`just packaging build-deb <version>`, and
`just packaging build-appimage <version>`.
`just packaging build-linux-artifacts <version>` builds both Linux formats
without compiling the shared Flutter bundle twice. Linux
build dependencies and the Flutter/Android toolchains must already be
installed as described in AGENTS.md. The release workflow calls these recipes
too, keeping local and published builds on the same path. APK output is under
`frontend/build/app/outputs/flutter-apk/`; Linux packages default to `dist/`,
or accept a different output directory as their second argument.

A `version` job computes the release version once (the tag with its
leading `v` stripped) so every artifact and the GitHub Release itself agree
on the same string, then a final `release` job gathers everything into one
GitHub Release. First push to GHCR from a repo needs a one-time manual
step: the pushed package defaults to private regardless of the repo's own
visibility, so make it public from the package's own settings page on
GitHub if it should be downloadable without authentication.

## Module boundaries

`tach.toml` in each Python package enforces a one-way dependency graph (e.g.
`models -> services -> api`, never the reverse). It starts nearly empty and
fills in as each layer is added, rather than being written speculatively
ahead of code that doesn't exist yet.
