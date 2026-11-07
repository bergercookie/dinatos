# Running and testing

This page shows how to run Dinatos on your computer and how to test your
changes. Before you start, finish [Environment setup](environment-setup.md).
The project has a Python API (`backend/`) and a Flutter app (`frontend/`).

## Fastest path: `just dev`

```bash
cp .env.example .env
# edit .env: set POSTGRES_PASSWORD (no default),
# and DINATOS_ADMIN_EMAIL / DINATOS_ADMIN_PASSWORD so you have an account to log in with
just dev
```

`just dev` starts Postgres in Docker and runs the migrations. Then it runs the
backend (`http://127.0.0.1:8000`) and the frontend. Open
`http://127.0.0.1:8081`. Log in with the admin credentials that you set.

- To stop the backend and the frontend, press Ctrl+C. Postgres keeps running.
- To stop the containers and keep the data, run `just docker down`.
- To remove the containers, run `just dev-clean`.

Warning: `just dev-clean` **deletes the Postgres data volume**. Before you use
it on data you want to keep, read
[Upgrades and backups](../deploy/upgrades-and-backups.md).

## Running pieces separately

### Backend only

Use one of these two methods.

**Method 1: use a Postgres that you run yourself.**

```bash
docker run -d --name dinatos-pg -e POSTGRES_USER=dinatos -e POSTGRES_PASSWORD=dinatos \
    -e POSTGRES_DB=dinatos -p 5432:5432 postgres:16-alpine
just backend migrate
just backend run   # http://127.0.0.1:8000, interactive API docs at /docs
```

`just backend run` reads `backend/.env` and `DINATOS_DATABASE_URL`. The
default is `postgresql+asyncpg://dinatos:dinatos@localhost:5432/dinatos`.

**Method 2: use Docker for the backend, the web app and Postgres together.**

```bash
just docker up     # http://127.0.0.1:8000; migrations run on start
just docker logs
just docker down   # keeps the data volume
```

This method also builds the Flutter web app. It is slow if you change only
the backend. For backend-only changes, use Method 1. For more information, see
[Deploying with Docker Compose](../deploy/quickstart.md).

### Frontend only

```bash
cd frontend
just install
just run   # flutter run -d web-server --web-port 8081, with hot reload
```

Open `http://127.0.0.1:8081`. The **Server URL** field on the login screen
tells the app which backend to use. The default is `http://127.0.0.1:8000`. To
hot-reload only the frontend, set the field to the backend of a `just dev`
run. For more information, see [Getting started](../user-guide/getting-started.md).

### Creating an account for testing

On first start, the backend creates an admin account from
`DINATOS_ADMIN_EMAIL` and `DINATOS_ADMIN_PASSWORD`. If you do not set these
variables, the first account that you register on a new instance becomes the
admin account.

To register an account and call the API, run these commands:

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

Every endpoint except `/health` and `/auth/*` needs the bearer token. For more
information, see [Authentication](../architecture/backend.md#authentication).

## Testing

| Command | What it tests | Needs |
|---|---|---|
| `just check` | Lint, backend and MCP server tests, docs build (the `check` job of CI) | Python, `uv` |
| `just backend test` | Backend tests only | Python, `uv` |
| `just frontend check` | Format, `flutter analyze`, `flutter test` | Flutter SDK |
| `just backend test-migrations` | Database migrations | Docker |
| `just e2e test` | The real web build in a browser | Docker, Flutter SDK |

`just check` does not run the frontend suites or the Docker-based suites,
because they are heavy. CI runs each of them as a separate job. See
[CI and releases](ci-and-releases.md).

### Backend tests

- The tests run on in-memory sqlite. They do not need Postgres.
- The shared `client` fixture (`backend/tests/conftest.py`) registers a
  throwaway user. It returns an `AsyncClient` that is already logged in. To
  test behavior without a login, use the `anonymous_client` fixture.
- Each test file name must be unique in `backend/tests/`. The directory has no
  `__init__.py` files. If two files have the name `test_auth.py`, collection
  fails with "import file mismatch". For this reason, the files are
  `api/test_auth.py` and `services/test_auth_service.py`.
- A new database table must be in `BACKED_UP_TABLES` in
  `backend/src/dinatos_backend/services/backup.py`. You can put it in
  `EXCLUDED_TABLES` instead, with a reason. If the table is in neither,
  `just test` fails. Also add user-owned fields to the `Exported*` models in
  `schemas/backup.py` and to `services/user_export.py`. See
  [Backup and data export](../architecture/backend.md#backup-and-data-export).
- Coverage needs `concurrency = ["greenlet"]` in `[tool.coverage.run]`
  (`backend/pyproject.toml`). The async engine of SQLAlchemy switches
  contexts through `greenlet`. Without this setting, coverage stops counting
  the lines of a function after its first `await db...`. If coverage drops
  sharply after you change database code, check this setting first.

### Migration tests

A migration is a versioned script (Alembic) that changes the database schema.
`just backend test-migrations` runs
[pytest-alembic](https://pytest-alembic.readthedocs.io/) against a throwaway
Postgres. `testcontainers` starts this Postgres. The suite checks four things:

- The repository has a single head revision.
- A clean upgrade from an empty database to head works.
- The models match what the migrations produce.
- `test_up_down_consistency` upgrades and downgrades every migration, one at a
  time.

The last check is the most important. It found a `downgrade()` that left a
Postgres ENUM type behind. This broke the next `upgrade()`. Sqlite cannot
show this problem, so the suite needs real Postgres. The suite is outside
`backend/tests/`. `just check` does not run it. CI runs it as the `migrations`
job.

To create a migration after you change a model, start a Postgres. Then run
these commands:

```bash
just backend revision "add widget table"
just backend check-migrations   # fails if models and migrations diverge
```

The Alembic configuration is in `backend/pyproject.toml`, in `[tool.alembic]`.
The file `backend/alembic.ini` exists only for the logging sections. Do not
add an `[alembic]` section to it. If a key is in both files, the value from
the ini file wins without a warning.

### End-to-end tests

`just e2e test` builds the web app and starts a throwaway Postgres. It also
starts a backend that serves the build. Then it drives the app in Chromium
with Playwright. To iterate on the tests only, set these variables:

| Variable | Effect |
|---|---|
| `E2E_WEB_DIR=<built build/web>` | Skips the Flutter build |
| `E2E_DATABASE_URL=<asyncpg URL>` | Skips Docker |
| `E2E_CHROMIUM_PATH=<chrome binary>` | Uses this browser when Playwright cannot download its own browser ("Executable doesn't exist") |

Flutter web paints to a `<canvas>`. For this reason, Playwright finds
elements through the accessibility tree of Flutter. Keep these rules in mind
when you write browser tests:

- Start Chromium with `channel="chromium"`. The default headless shell has no
  WebGL support, which Flutter needs. With the shell, the page stays blank and
  shows no error. If a TLS-intercepting proxy is in your network, add
  `--ignore-certificate-errors` on your computer. Do not commit it.
- Use `get_by_role(...)` locators. Do not use pixel coordinates. The roles
  are: `textbox` for text fields, `checkbox` for checkboxes, `button` for
  buttons and FABs, `menuitem` for menu items, and `tab` for bottom-bar tabs.
  A `Card` is a `group` with the name of its label. An icon-only button needs
  a `tooltip:` to get a name.
- Type with `press_sequentially()`. Do not use `fill()`. Flutter copies its
  own controller state back to the `<input>`. This can replace a filled value
  with an empty value before Flutter sees it. If the field can already hold
  text, select all and delete first.
- The `NavigationRail` of the wide layout is not in the accessibility tree.
  The e2e tests press it by coordinates. The bottom bar is in the tree.
- A click through the accessibility tree reaches the app as a semantic tap,
  not as pointer events. A `Listener` or `onPointerUp` never sees it.
- Playwright does not click an element that another element covers. A modal
  tour scrim is an example. To test that a click is blocked, expect a click
  with a short timeout to time out. Do not use `force=True`.
- The build uses `--no-web-resources-cdn`. Without it, Flutter gets CanvasKit
  from the CDN of Google. If the browser has no internet access, the page
  never renders.
- A password-manager extension fills fields with synthetic `input` and
  `change` events. By default, Flutter web ignores these events. A new form
  that must work with an extension needs the wrapper
  `WebAutofillSemantics(fields: ...)`. The wrapper matches fields by their
  label. `e2e/test_autofill.py` reproduces the behavior of an extension.

## Things only a real browser or device shows

`flutter test` and `flutter analyze` cannot find these problems. When you
change one of these areas, load the built app:

- **CORS.** `flutter test` makes no cross-origin request. A missing CORS
  policy shows only as a failed preflight request in a browser. To check a web
  change, run `flutter build web --release`. Serve `build/web/`. Open it
  against a running backend.
- **Android release permission.** `flutter create` adds `INTERNET` only to the
  debug and profile manifests. A release APK without this permission in
  `frontend/android/app/src/main/AndroidManifest.xml` installs. Then every
  request fails with "server not reachable". To check the permission on a
  built APK without an emulator, run `just android check-apk`.
- **Keyring on Linux desktop.** If the keyring is locked or missing,
  `flutter_secure_storage` throws on every call. `TokenStorage` and
  `ServerUrlStorage` (`frontend/lib/core/`) catch this error on purpose. Keep
  the catches.

## Pitfalls when you edit build files

- **Dockerfile.** The last `uv sync --locked --no-dev` needs `--no-editable`.
  Without it, the virtual environment of the runtime image points to a path
  of the build stage that does not exist. Then `import dinatos_backend` fails
  when the container starts, although `docker build` succeeds. Always run the
  built image against Postgres. If a TLS-intercepting proxy is in your
  network, you can pass its CA bundle to the build (`PIP_CERT`,
  `SSL_CERT_FILE`). Do not commit this.
- **Seed data for global tables** (for example `exercises`). Use a fresh
  database for each run. A second "Bench Press" breaks the unique constraint.
  For this reason, `screenshots/generate.py` uses a disposable Postgres.
- **`flutter create --platforms=...` in this project.** The command replaces
  the migration list in `frontend/.metadata` and removes the other platforms.
  After the command, compare `.metadata` and `analysis_options.yaml` with
  the old files. Restore the lost entries.
- **Authentication.** Sessions are server-side rows (`AuthSession`) with
  opaque random tokens. They are not JWTs. For this reason, a logout revokes
  the session. Do not add JWT signing again before you read
  [Authentication](../architecture/backend.md#authentication). Use only Argon2
  for passwords. Never use a fast hash such as SHA-256 for a password.
  SHA-256 is correct for session tokens and for CSV content hashes, because
  these values have high entropy.

Next: [CI and releases](ci-and-releases.md).
