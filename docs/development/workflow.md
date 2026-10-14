# Running and testing

How to run Dinatos locally and test your changes. Assumes you finished
[Environment setup](environment-setup.md). The project is a Python API
(`backend/`) plus a Flutter app (`frontend/`).

## Fastest path: `just dev`

```bash
cp .env.example .env
# edit .env: set POSTGRES_PASSWORD (no default),
# and DINATOS_ADMIN_EMAIL / DINATOS_ADMIN_PASSWORD so you have an account to log in with
just dev
```

This starts Postgres in Docker, runs migrations, then runs the backend
(`http://127.0.0.1:8000`) and the frontend. Open `http://127.0.0.1:8081` and
log in with the admin credentials you set.

- Ctrl+C stops the backend and frontend. Postgres keeps running.
- `just docker down` stops the containers and keeps the data.
- `just dev-clean` removes the containers and **deletes the Postgres data
  volume**. Read [Upgrades and backups](../deploy/upgrades-and-backups.md)
  before using it on data you care about.

## Running pieces separately

### Backend only

Pick one.

**Against a Postgres you run yourself:**

```bash
docker run -d --name dinatos-pg -e POSTGRES_USER=dinatos -e POSTGRES_PASSWORD=dinatos \
    -e POSTGRES_DB=dinatos -p 5432:5432 postgres:16-alpine
just backend migrate
just backend run   # http://127.0.0.1:8000, interactive API docs at /docs
```

`just backend run` reads `backend/.env` and `DINATOS_DATABASE_URL`. The
default is `postgresql+asyncpg://dinatos:dinatos@localhost:5432/dinatos`.

**In Docker (backend, web app and Postgres together):**

```bash
just docker up     # http://127.0.0.1:8000; migrations run on start
just docker logs
just docker down   # keeps the data volume
```

This builds the Flutter web app too, so it is slow for backend-only edits.
Prefer `just backend run` for those. See
[Deploying with Docker Compose](../deploy/quickstart.md).

### Frontend only

```bash
cd frontend
just install
just run   # flutter run -d web-server --web-port 8081, with hot reload
```

Open `http://127.0.0.1:8081`. The **Server URL** field on the login screen
(default `http://127.0.0.1:8000`) tells the app which backend to use. Point it
at a `just dev` backend to hot-reload the frontend alone. See
[Getting started](../user-guide/getting-started.md).

### Creating an account for testing

`DINATOS_ADMIN_EMAIL` and `DINATOS_ADMIN_PASSWORD` create an admin account on
first start. Without them, the first account registered on a fresh instance
becomes admin:

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

Every endpoint except `/health` and `/auth/*` needs that bearer token. See
[Authentication](../architecture/backend.md#authentication).

## Testing

| Command | Tests | Needs |
|---|---|---|
| `just check` | Lint, backend and MCP server tests, docs build (what CI's `check` job runs) | Python, `uv` |
| `just backend test` | Backend tests only | Python, `uv` |
| `just frontend check` | Format, `flutter analyze`, `flutter test` | Flutter SDK |
| `just backend test-migrations` | Database migrations | Docker |
| `just e2e test` | The real web build in a browser | Docker, Flutter SDK |

`just check` leaves out the frontend and Docker-based suites because they are
heavy. CI runs each as its own job; see [CI and releases](ci-and-releases.md).

### Backend tests

- They run on in-memory sqlite. No Postgres needed.
- The shared `client` fixture (`backend/tests/conftest.py`) registers a
  throwaway user and returns an already logged-in `AsyncClient`. Use the
  `anonymous_client` fixture to test unauthenticated behavior.
- Test file names must be unique across `backend/tests/`: there are no
  `__init__.py` files, so two `test_auth.py` files fail collection with
  "import file mismatch". Hence `api/test_auth.py` and
  `services/test_auth_service.py` differ in name.
- **A new database table must be added to `BACKED_UP_TABLES`** in
  `backend/src/dinatos_backend/services/backup.py` (or to `EXCLUDED_TABLES`
  with a reason), or `just test` fails. Also add user-owned fields to the
  `Exported*` models in `schemas/backup.py` and to `services/user_export.py`.
  See [Backup and data export](../architecture/backend.md#backup-and-data-export).
- Coverage needs `concurrency = ["greenlet"]` in `[tool.coverage.run]`
  (`backend/pyproject.toml`). SQLAlchemy's async engine switches through
  `greenlet`, and without that setting coverage silently stops counting a
  function's lines after its first `await db...`. If coverage drops sharply
  after you touch DB code, check this setting before assuming a regression.

### Migration tests

A migration is a versioned script (Alembic) that changes the database schema.
`just backend test-migrations` runs [pytest-alembic](https://pytest-alembic.readthedocs.io/)
against a throwaway Postgres (started by `testcontainers`). It checks:

- a single head revision;
- a clean upgrade from empty to head;
- that the models match what the migrations produce;
- `test_up_down_consistency`, which upgrades and downgrades every migration
  one at a time.

The last check matters most. It caught a `downgrade()` that left a Postgres
ENUM type behind and broke the next `upgrade()`. Sqlite cannot reproduce that,
so it needs real Postgres. The suite is outside `backend/tests/` and not part
of `just check`; CI runs it as the `migrations` job.

To create a migration after changing a model (needs a running Postgres):

```bash
just backend revision "add widget table"
just backend check-migrations   # fails if models and migrations diverge
```

Alembic's own config lives in `backend/pyproject.toml` under `[tool.alembic]`.
`backend/alembic.ini` exists only for logging sections. Do not add an
`[alembic]` section to it: a key in both places lets the ini value win
silently.

### End-to-end tests

`just e2e test` builds the web app, starts a throwaway Postgres and a backend
serving that build, then drives it in Chromium with Playwright. Escape hatches
for iterating on the tests alone:

| Variable | Effect |
|---|---|
| `E2E_WEB_DIR=<built build/web>` | Skip the Flutter build |
| `E2E_DATABASE_URL=<asyncpg URL>` | Skip Docker |
| `E2E_CHROMIUM_PATH=<chrome binary>` | Use this browser when Playwright's own can't be downloaded ("Executable doesn't exist") |

Gotchas when writing browser tests. Flutter web paints to a `<canvas>`, so
Playwright finds elements through Flutter's accessibility tree:

- Launch Chromium with `channel="chromium"`. The default headless shell lacks
  the WebGL support Flutter needs and renders a permanently blank page with no
  error. Behind a TLS-intercepting proxy, add `--ignore-certificate-errors`
  locally; never commit it.
- Use `get_by_role(...)` locators, not pixel coordinates. Roles: text fields
  `textbox`, checkboxes `checkbox`, buttons and FABs `button`, menu items
  `menuitem`, bottom-bar tabs `tab`, a `Card` is a `group` named after its
  label. Icon-only buttons need a `tooltip:` to have a name at all.
- Type with `press_sequentially()`, not `fill()`. Flutter mirrors its own
  controller state back onto the `<input>`, so `fill()` can be overwritten
  with an empty value before Flutter sees it. Select-all and delete first if
  the field may already hold text.
- The wide layout's `NavigationRail` is missing from the accessibility tree,
  so e2e tests press it by coordinates. The bottom bar is fine.
- A click through the accessibility tree reaches the app as a semantic tap,
  not pointer events. A `Listener`/`onPointerUp` never sees it.
- Playwright refuses to click an element another element covers (such as a
  modal tour's scrim). To test "blocked", expect a short-timeout click to time
  out; do not use `force=True`.
- The build uses `--no-web-resources-cdn`. Without it Flutter fetches
  CanvasKit from Google's CDN and, with no internet in the browser, the page
  never renders.
- A password-manager extension fills fields with synthetic `input`/`change`
  events, which Flutter web ignores by default. Any new form that should work
  with one needs the `WebAutofillSemantics(fields: ...)` wrapper (fields are
  matched by label). `e2e/test_autofill.py` reproduces the extension's
  behavior.

## Things only a real browser or device shows

`flutter test` and `flutter analyze` cannot catch these, so load the built app
when you change them:

- **CORS.** `flutter test` makes no cross-origin request. A missing policy
  shows up only as a failed preflight in a browser. To check a web change:
  `flutter build web --release`, serve `build/web/`, open it against a running
  backend.
- **Android release permission.** `flutter create` adds `INTERNET` only to the
  debug and profile manifests. A release APK without it in
  `frontend/android/app/src/main/AndroidManifest.xml` installs fine, then every
  request fails as "server not reachable". `just android check-apk` verifies
  the permission on a built APK with no emulator.
- **Keyring on Linux desktop.** A locked or missing keyring makes
  `flutter_secure_storage` throw on every call. `TokenStorage` and
  `ServerUrlStorage` (`frontend/lib/core/`) catch that on purpose. Keep the
  catches.

## Pitfalls when editing build files

- **Dockerfile.** The final `uv sync --locked --no-dev` needs `--no-editable`.
  Otherwise the runtime image's venv points at a build-stage path that does not
  exist, and `import dinatos_backend` fails at container start, even though
  `docker build` succeeds. Always run the built image against Postgres. Behind
  a TLS-intercepting proxy you may need to pass its CA bundle in
  (`PIP_CERT`, `SSL_CERT_FILE`); never commit that.
- **Seed data for global tables** (such as `exercises`) needs a fresh database
  per run. A second "Bench Press" violates the unique constraint.
  `screenshots/generate.py` uses a disposable Postgres for this reason.
- **`flutter create --platforms=...` on this project** overwrites
  `frontend/.metadata`'s migration list, dropping the other platforms. Diff
  `.metadata` and `analysis_options.yaml` afterwards and restore.
- **Auth.** Sessions are server-side rows (`AuthSession`) with opaque random
  tokens, not JWTs, so logout truly revokes a session. Do not reintroduce JWT
  signing without reading
  [Authentication](../architecture/backend.md#authentication). Passwords use
  Argon2 only; never a fast hash such as SHA-256. SHA-256 is correct for
  session tokens and CSV content hashes, which are high-entropy.

Next: [CI and releases](ci-and-releases.md).
