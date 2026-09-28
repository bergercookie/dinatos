# Environment setup

Two ways to get a working environment. Devbox is recommended and is what
`./tools/install-devbox.sh` sets up for you; the manual path exists for
whoever can't or doesn't want to install Devbox, and documents exactly what
Devbox is giving you for free.

## Devbox (recommended)

[Devbox](https://www.devbox.dev) provisions every tool a `just` recipe might
need -- Python 3.12, `uv`, a current `just`, Docker tooling, the Flutter SDK,
CMake -- into an isolated shell, pinned by `devbox.lock`, without touching
your system installs.

```bash
./tools/install-devbox.sh   # installs Devbox itself if missing, runs `devbox install`
devbox shell                 # enter the pinned environment
just install                 # backend virtualenv (uv sync)
just check
```

`devbox.json` pins `python@3.12` exactly; `cmake`, `dart`, `flutter`, `git`,
`just`, and `uv` float at `@latest` -- if a recipe starts failing only inside
`devbox shell` and not for someone else, a version drift in one of those is
the first thing to check (`devbox update` to pull the latest pinned set).

Docker itself is not something Devbox provides a daemon for -- it exposes
your **host's** Docker socket, so `just docker up` and
`just backend test-migrations` need Docker actually running on the host,
inside `devbox shell` or not.

**"Modules are currently unstable" error even inside `devbox shell`** means
you're not actually in it -- run `just --version` to confirm (should be
>= 1.31; see "Manual setup" below for why that number matters).

## Manual setup

### `just` must be recent enough for `mod`

The root `justfile` imports each package's own `justfile` with
`mod backend 'backend/justfile'`. That directive needs modules support,
which was *unstable* before `just`'s 1.3x releases. Ubuntu's own
`apt install just` (noble, as of this writing) installs **1.21.0**, which
refuses to run at all with a "Modules are currently unstable" error and no
clean way to opt in from the justfile itself.

If `just --version` reports anything before roughly 1.31, don't try to work
around it with `--unstable` or `JUST_UNSTABLE=1` -- get a current build
instead:

```bash
cargo install just --locked   # if a Rust toolchain is already present
```

or the install script from <https://github.com/casey/just#installation>. CI
does not hit this: `extractions/setup-just@v4` fetches a current release.

### Python / `uv`

Nothing beyond Python and [`uv`](https://docs.astral.sh/uv/) is needed for
the backend and docs:

```bash
just install   # create the backend virtualenv
just check     # lint, test, build docs -- everything CI runs for backend+docs
```

### Docker

Needed for `just docker up`/`just dev` (a real Postgres) and
`just backend test-migrations` (a throwaway Postgres via `testcontainers`).
If `docker ps` reports it can't connect to the daemon, start it rather than
concluding Docker is unavailable: `sudo dockerd > /tmp/dockerd.log 2>&1 &` in
a container that doesn't run it as a service.

### Flutter SDK

`frontend/` needs a real Flutter SDK on `PATH` -- there is no `apt` package
for it. In a fresh container:

```bash
curl -o /tmp/flutter.tar.xz \
    https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_<version>-stable.tar.xz
tar -xf /tmp/flutter.tar.xz -C /opt   # -> /opt/flutter/bin/flutter
export PATH="/opt/flutter/bin:$PATH"
git config --global --add safe.directory /opt/flutter   # else "detected dubious ownership"
flutter config --no-analytics && dart --disable-analytics
```

Look up the current stable version and archive URL at
[the Flutter releases JSON](https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json)
rather than hardcoding one, since it moves. Running as root prints a
harmless "Woah! You appear to be trying to run flutter as root" banner on
every invocation.

`just frontend check`/`test` do **not** need Chrome or the Android SDK:
`flutter test` runs headless against a built-in test harness, not a real
device or browser, and `flutter analyze`/`dart format` don't need a device
either. Only `flutter run`/`build` for a specific platform need that
platform's toolchain -- see
[CI and releases](ci-and-releases.md) for what each release artifact needs.

### `.env` files

Two separate files, read by different things:

- Repo-root `.env` (from `.env.example`) -- read by `docker compose` and by
  `just dev` (which loads it into the recipe's own environment too, via
  `set dotenv-load`). Needs `POSTGRES_PASSWORD` at minimum; the containers
  refuse to start without it.
- `backend/.env` (from `backend/.env.example`) -- read by `just backend run`
  when running the backend directly against a Postgres you started some
  other way. Every setting there has a default; nothing is required.

Both are git-ignored.

## What needs nothing beyond this

```bash
just install
just check     # lint, test, docs -- everything CI runs, no database needed
```

`just test` runs against an in-memory sqlite database (see
`backend/tests/conftest.py`), never a real Postgres. See
[Running and testing](workflow.md) for everything that *does* need one.
