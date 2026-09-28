# For coding agents

This repo is friendly to an agent working unattended in a fresh, ephemeral
container: `just install && just check` needs nothing but Python, `uv`, and a
recent `just`.

This file is environment gotchas and non-obvious failure modes -- the things
that break silently or confusingly in a fresh/unattended container. For the
human-facing narrative (how to set up a normal dev environment, what CI
checks, PR expectations), see `CONTRIBUTING.md`; for why the code is built
the way it is, see `docs/architecture/` (rendered as part of the Sphinx
site, readable in place too). A fact belongs in exactly one of these three
places -- if you're about to duplicate something from here into one of
those, cross-reference instead.

## `just` must be recent enough for `mod`

The root `justfile` imports each package's own `justfile` with `mod backend
'backend/justfile'`. That directive needs modules support, which was
*unstable* before just's 1.3x releases. Ubuntu's own `apt install just`
(noble, as of this writing) installs **1.21.0**, which refuses to run at all
with a "Modules are currently unstable" error and no clean way to opt in from
the justfile itself.

If `just --version` reports anything before roughly 1.31, don't try to work
around it with `--unstable` or `JUST_UNSTABLE=1` -- get a current build
instead, e.g.:

```bash
cargo install just --locked   # if a Rust toolchain is already present
```

or the install script from <https://github.com/casey/just#installation>.
CI does not hit this: `extractions/setup-just@v4` fetches a current release.

## What needs nothing extra

```bash
just install
just check     # lint, test, docs -- everything CI runs
```

`just test` still needs nothing but that: the suite runs against an
in-memory sqlite database (see `tests/conftest.py`), never a real Postgres.
Every endpoint but `/health` and `/auth/*` now requires a bearer token, so
the shared `client` fixture registers and logs in a throwaway user before
handing back an already-authenticated `AsyncClient`; a test that needs to
check unauthenticated behavior itself asks for `anonymous_client` instead.

## Coverage requires `concurrency = ["greenlet"]`

SQLAlchemy's async engine bridges every DBAPI call through `greenlet`. Without
`concurrency = ["greenlet"]` in `[tool.coverage.run]` (backend/pyproject.toml),
coverage.py silently stops tracking a function's lines *after* its first
`await db.something(...)` -- not just under-reporting a little, entire tail
ends of correct, tested router functions show up as 0% covered. If a fresh
`just backend test` ever reports a big unexplained coverage drop right after
touching DB code, check this setting is still there before assuming the code
regressed.

## A real Postgres is needed for anything beyond `just test`

`just run`, `just migrate`, `just revision` and `just check-migrations` (all
in `backend/justfile`) talk to a real database via `DINATOS_DATABASE_URL`
(default: `postgresql+asyncpg://dinatos:dinatos@localhost:5432/dinatos`; see
`backend/.env.example`). `just docker up` (root `justfile`, `docker-compose.yml`)
starts one for you alongside the backend itself; needs `.env` first (copy
`.env.example`, `POSTGRES_PASSWORD` has no default and the containers
refuse to start without it). Without Docker, start one yourself:

```bash
docker run -d --name dinatos-pg -e POSTGRES_USER=dinatos -e POSTGRES_PASSWORD=dinatos \
    -e POSTGRES_DB=dinatos -p 5432:5432 postgres:16-alpine
cd backend && uv run alembic upgrade head
```

Every other `Settings` field has a default too (see config.py), so
constructing it never needs anything set beyond `DINATOS_DATABASE_URL`
pointing at a real Postgres for the commands above.

## The Dockerfile needs `--no-editable` on its second `uv sync`

`backend/Dockerfile` is a two-stage build: `uv sync` in the builder stage,
then only `.venv/` is copied into the runtime stage. `uv sync`'s default
install of the project itself is *editable* -- a path reference back to
`/app/src` in the builder stage's filesystem, not a real package -- so
without `--no-editable` on the final `uv sync --locked --no-dev` (after
`src/` is copied in), the runtime image's venv points at a directory that
does not exist there, and every import of `dinatos_backend` fails with
`ModuleNotFoundError` at container start. Caught by actually running the
built image against a real Postgres, not just `docker build` succeeding --
a broken editable install still builds fine; it only fails when something
tries to `import dinatos_backend`.

Building the image needs real internet access (PyPI, Docker Hub); a
sandboxed session behind a TLS-intercepting proxy may need its CA bundle
threaded into the build (`PIP_CERT`/`SSL_CERT_FILE`) to verify this works at
all -- that's an environment-verification workaround, never something to
add permanently to the committed Dockerfile itself.

## Migrations have their own test suite: `just backend test-migrations`

`backend/tests_migrations/` (deliberately outside `backend/tests/`, so
`just test`/`just check` never touch it) runs pytest-alembic's built-in
suite against a real, throwaway Postgres spun up by `testcontainers`: a
single head revision, a clean base->head upgrade, the models matching the
DDL the migrations produce, and -- the one that matters most --
`test_up_down_consistency`, which upgrades and downgrades *every* migration
individually, not just head<->base. That last one is how the enum-type-
left-behind bug (see the initial migration's `downgrade()` and the
Hevy-import-records one's) was actually caught, and a sqlite-backed test
would never have caught it, since sqlite has no `CREATE TYPE` to forget to
undo in the first place. This suite used to be a hand-rolled version of just
that one test; pytest-alembic's covers strictly more for less code to
maintain.

It needs Docker (for testcontainers to launch a container) -- if `docker ps`
reports it cannot connect to the daemon, start it rather than concluding
Docker is unavailable: `sudo dockerd > /tmp/dockerd.log 2>&1 &`. Not part of
`check` because of that, and because it takes real seconds; CI runs it as
its own `migrations` job instead.

## Alembic's own config lives in pyproject.toml, not alembic.ini

`backend/pyproject.toml`'s `[tool.alembic]` holds `script_location` and
anything else Alembic itself needs -- this needs `alembic>=1.16`, which
added reading `[tool.alembic]` out of pyproject.toml (`Config`'s `toml_file`
argument). `backend/alembic.ini` still exists, but only for the `[loggers]`/
`[handlers]`/`[formatters]` sections `env.py`'s `logging.config.fileConfig()`
call needs -- that stdlib function only understands the ini format, so
that's the one piece with nowhere else to go. Don't add anything back to
alembic.ini's `[alembic]` section (it doesn't have one anymore): a key that
exists in *both* places has the ini value win, silently shadowing
pyproject.toml, which defeats the point of having moved it.

## Auth: a real server-side session, not a self-verifying token

`AuthSession` (one row per login) is what makes `POST /auth/logout` real:
it revokes exactly the session named by the caller's bearer token, and
every other session the same account has open elsewhere is unaffected.
The token itself is opaque (`secrets.token_urlsafe`), not a JWT -- an
earlier version of this signed a stateless `{"sub": user_id, "exp": ...}`
JWT instead, verified by signature and expiry alone with no database
lookup, specifically to avoid a per-request session check. That trade
was reversed on purpose (see `docs/architecture/backend.md`'s "Authentication"
section for the full reasoning): once `get_current_user` needs a database
read either way (to reload the `User` row so a deleted account's token
stops working immediately), a signed self-verifying token buys nothing a
plain random one doesn't -- so don't reintroduce JWT-signing machinery
(`pyjwt`, a `jwt_secret_key` setting) to "optimize" this without re-reading
that reasoning first.

`services/auth.py` has the actual mechanics: `generate_session_token`
(the raw token, shown to the client exactly once), `hash_session_token`
(SHA-256 of it, the only thing ever stored), `create_session`/
`get_valid_session`/`revoke_session`. `get_valid_session`'s expiry check
runs as SQL (`AuthSession.expires_at > func.now()`), not a Python-side
`datetime.now()` comparison -- avoids any timezone-awareness mismatch
between what a DB driver hands back and what Python considers "now",
consistent with `TimestampMixin` using `server_default=func.now()` rather
than an application-set timestamp.

`argon2-cffi` hashes passwords -- never swap this for a fast general-purpose
hash (BLAKE3, SHA-256, etc.) to save time: those are fast *by design*, which
is exactly wrong for password storage, since it lets anyone who steals the
`users.password_hash` column brute-force it at GPU speed. Argon2's slowness
is the point. A fast hash is the *right* tool for the session token above
(and for `services/hevy_import.hash_csv_content`) -- both hash high-entropy
random values or content, not a low-entropy human password, so there's
nothing to brute-force regardless of hash speed. Never confuse the two
directions: Argon2 only for a password, plain SHA-256 everywhere else.

`tests/api/test_auth.py` (the API-level auth flow tests) and
`tests/services/test_auth_service.py` (the service-level ones) are
deliberately *not* both named `test_auth.py`: `tests/` has no `__init__.py`,
so pytest's rootless import mode requires every test module in the tree to
have a unique basename -- two files named identically anywhere under
`tests/` fail collection with "import file mismatch", not a normal test
failure.

## Frontend needs the Flutter SDK, not apt's Dart/Flutter (there isn't one)

`frontend/` needs a real Flutter SDK on `PATH`; nothing in this repo
installs one for you. In a fresh, unattended container:

```bash
curl -o /tmp/flutter.tar.xz \
    https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_<version>-stable.tar.xz
tar -xf /tmp/flutter.tar.xz -C /opt   # -> /opt/flutter/bin/flutter
export PATH="/opt/flutter/bin:$PATH"
git config --global --add safe.directory /opt/flutter   # else "detected dubious ownership"
flutter config --no-analytics && dart --disable-analytics
```

(Look up the current stable version+archive at
`https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json`
rather than hardcoding one here, since it moves.) Running as root prints a
harmless "Woah! You appear to be trying to run flutter as root" banner on
every invocation -- expected in a container, not an error.

`just frontend test`/`check` do **not** need Chrome or the Android SDK:
`flutter test` runs headless against a built-in test harness ("flutter
tester"), not a real device or browser. `flutter analyze`/`dart format`
don't need a device either. Only `flutter run`/`build` for a specific
platform (`-d chrome`, `-d web-server`, `apk`) need that platform's
toolchain -- `web-server` (what `just frontend run` uses) needs neither
Chrome nor the Android SDK, since it just serves the build and lets any
browser connect to it.

This is also why `just frontend check` is not part of the root `just
check`/CI job -- see the root `justfile`'s comment on `check` and the `ci.yml`
`frontend` job: the Flutter SDK is a much heavier, non-`uv` dependency than
anything else `just check` needs, so it stays a separate recipe and CI job,
same reasoning as `backend::test-migrations` needing Docker.

## The web target needs the backend's CORS middleware -- verified by actually loading it in a browser

`flutter analyze` and `flutter test` are enough to catch most regressions,
but neither one makes a real cross-origin HTTP request, so neither one can
catch a missing CORS policy -- that only shows up when the built app is
actually loaded in a browser and it tries to call the backend from a
different origin. That's exactly how the `CORSMiddleware` in
`backend/src/dinatos_backend/main.py` got added: `flutter build web`
succeeded, `flutter test` passed, and the app still failed at the first
`/auth/register` call with a generic "could not reach the server" -- the
browser's console showed the real reason (`net::ERR_FAILED` on a preflight
`OPTIONS` request), which a Dio exception alone doesn't surface. If a
frontend change to how the API is called seems to work in `flutter test`
but you haven't loaded the actual built app in a browser against a running
backend, you haven't verified it -- `flutter build web --release`, serve
`build/web/` with any static file server, and open it.

A headless Chromium works fine for this in a sandboxed/CI-like environment
that has no display and no `google-chrome` on `PATH`, but Playwright's
*default* headless launch picks its lightweight "headless shell" binary,
which lacks the GPU/WebGL support CanvasKit (Flutter web's renderer) needs --
the app fetches and runs fine, every request 200s, and it still paints
nothing: a permanently blank page with no error anywhere. Force the full
Chrome-for-Testing binary instead with `channel="chromium"` on `launch()`.
`--ignore-certificate-errors` is needed in a sandbox sitting behind a
TLS-intercepting proxy the browser doesn't otherwise trust (the same class
of issue as the Dockerfile's `PIP_CERT` workaround above) -- an
environment-verification flag, not something to wire into the app itself
or commit (see `screenshots/generate.py`, which deliberately omits it: real
CI has no such proxy).

Flutter web renders to a `<canvas>` (CanvasKit), not real DOM text nodes,
but it does expose a real accessible-name/role tree for assistive tech --
Playwright's `get_by_role(role, name=...)` locators find elements through
that tree, and are far more robust than driving it by pixel coordinates off
a screenshot. Two things are needed first: (1) that tree isn't built until
something clicks the offscreen `flt-semantics-placeholder` element Flutter
renders for exactly this purpose (`dispatch_event("click")`, since
`.click()` refuses an offscreen target); (2) icon-only buttons need a
`tooltip:` (or similar) to have any accessible name at all. Empirically:
text fields and checkboxes are `role="textbox"`/`"checkbox"`; buttons,
FABs and menu items are `role="button"`/`"menuitem"`; bottom
`NavigationDestination` tabs are `role="tab"`, not `"button"`; and a `Card`
gets `role="group"` with the card's own label as its name, so a nested
exercise card's fields are reachable via
`page.get_by_role("group", name="Bench Press").get_by_role(...)`.

Filling a text field also needs care: `Locator.fill()` sets the DOM
`<input>`'s value in one shot and returns as soon as it dispatches a single
`input` event, but Flutter's web engine mirrors its own
`TextEditingController` state back onto that same `<input>` on every
rebuild (e.g. to run a validator) -- a bulk `.fill()` can lose that race and
get silently overwritten back to empty before Flutter's JS<->Dart channel
has processed it, surfacing as a real "Name is required" error on a field
that was just filled. Typing character-by-character with real key events
(`Locator.press_sequentially`), the way a person would, avoids the race
entirely; select-all-then-delete first if the field might already hold a
value (e.g. one copied from a saved workout) rather than being empty.

Seed data for anything backed by a genuinely global (not per-owner) table --
`exercises` is the example here -- needs a fresh database per run, not a
shared or long-lived one: two runs both creating an exercise named "Bench
Press" is a real unique-constraint violation the second time, not a
harmless no-op. `screenshots/generate.py` uses a disposable testcontainers
Postgres for exactly this reason.

## The Linux desktop target needs its own apt packages, not just the Flutter SDK

`flutter build linux` (added for `packaging/linux/`'s `.deb`/AppImage, see
`docs/architecture/distribution.md`) fails at the CMake
configure step without `libgtk-3-dev` (the renderer's windowing toolkit)
and `libsecret-1-dev` (what `flutter_secure_storage` links against on
Linux) already installed -- `clang cmake ninja-build pkg-config` cover the
rest of the toolchain itself. None of this is needed for
`flutter analyze`/`flutter test` (see above), only for actually building
this one platform target; `.github/workflows/release.yml`'s
`linux-packages` job installs all of it via `apt-get` before building.

A keyring that isn't running or unlocked -- true of many minimal
window-manager setups, not just headless CI -- makes
`flutter_secure_storage` throw `PlatformException` on every call instead of
ever returning null. `TokenStorage`/`ServerUrlStorage`
(`frontend/lib/core/`) both catch that and treat it as
"nothing stored"/"couldn't persist" for exactly this reason; don't remove
those catches to "simplify" the code without re-verifying this class of
environment first (a real, previously-unlogged crash: `main()`'s startup
read threw before `runApp()` ever ran).

`flutter create --platforms=linux .` on an existing project is not
purely additive: it rewrote `.metadata`'s migration list to contain only
`linux`, silently dropping the existing `android`/`web` entries, which had
to be restored by hand. Diff `.metadata` (and `analysis_options.yaml`, which
it also touches) after running this for any other platform, rather than
assuming it only adds what you asked for.

## Releases are cut by pushing a tag, not from `main` branch state directly

`.github/workflows/release.yml` triggers on `v*` tags and is the only
place the Docker image, `.deb`/AppImage, and Android APK get built and
published together -- there's no `just` recipe for "cut a release"; the
workflow's `version` job derives the version from the tag itself
(`${GITHUB_REF_NAME#v}`). Test any change to `packaging/linux/`'s scripts
or the Dockerfile locally before tagging: a failure partway through the
workflow (e.g. the `.deb` step failing after the Docker image already
pushed) leaves a real, partially-published state on GHCR with no automatic
rollback.
