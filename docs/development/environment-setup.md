# Environment setup

This page shows how to install the tools you need to build and test Dinatos.
You can use Devbox to install everything with one command. You can also
install the tools by hand. For the shortest path (Python, `uv` and `just`),
see [Contributing](index.md).

Every task in this repository is a [`just`](https://github.com/casey/just)
recipe. To see all recipes, run `just --list`. To run a recipe from the
`justfile` of a subdirectory, use `just <module> <recipe>`. For example, run
`just backend test`.

## What needs what

| You want to run | You need |
|---|---|
| `just install`, `just check` | Python 3.12, `uv`, `just` 1.31 or newer |
| `just backend test-migrations`, `just e2e test`, `just dev`, `just docker up` | Docker |
| `just frontend check`, `just e2e test`, `just screenshots generate` | Flutter SDK |

`just check` does not need a database. The backend tests use in-memory
sqlite.

## Devbox (recommended)

[Devbox](https://www.jetify.com/devbox) installs Python 3.12, `uv`, `just`,
Flutter, CMake and Git into an isolated shell. It does not change the
packages of your system.

```bash
./tools/install-devbox.sh   # installs Devbox if missing, then `devbox install`
devbox shell
just install
just check
```

- `devbox.json` pins `python@3.12`. The other tools use `@latest`. If a
  recipe fails only inside `devbox shell`, run `devbox update`.
- Devbox does not provide a Docker daemon. It uses the daemon of your host.
  Make sure Docker runs on the host.
- If you see the error "Modules are currently unstable", you are not in the
  Devbox shell, or your `just` is too old. To check, run `just --version`.

## Manual setup

### `just` 1.31 or newer

The root `justfile` loads the `justfile` of each package with `mod`. Before
`just` 1.31, `mod` was unstable. The `just` package from Ubuntu's `apt` is
version 1.21. It fails with the error "Modules are currently unstable".

Do not use `--unstable` or `JUST_UNSTABLE=1` as a workaround. Install a
current build:

```bash
cargo install just --locked
```

You can also use the [install script](https://github.com/casey/just#installation).
If a sandbox proxy blocks the script (error 403), download a release tarball
from GitHub. Version 1.43.0 works:

```bash
V=1.43.0
curl -sSfL "https://github.com/casey/just/releases/download/$V/just-$V-x86_64-unknown-linux-musl.tar.gz" \
    | tar -xzf - -C /usr/local/bin just
```

### Python and `uv`

Install Python 3.12 and [`uv`](https://docs.astral.sh/uv/). Then run these
recipes:

```bash
just install   # backend and MCP server virtualenvs (uv sync)
just check     # lint, tests, docs build
```

### Docker

The table in "What needs what" shows which recipes need Docker. If
`docker ps` cannot connect to the daemon, start the daemon. Do not assume
that Docker is missing.

```bash
sudo dockerd > /tmp/dockerd.log 2>&1 &
```

### Flutter SDK

The `frontend/` directory needs a real Flutter SDK in `PATH`. There is no
`apt` package for it.

```bash
curl -o /tmp/flutter.tar.xz \
    https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_<version>-stable.tar.xz
tar -xf /tmp/flutter.tar.xz -C /opt   # -> /opt/flutter/bin/flutter
export PATH="/opt/flutter/bin:$PATH"
git config --global --add safe.directory /opt/flutter   # else "dubious ownership"
flutter config --no-analytics && dart --disable-analytics
```

To find the current `<version>`, see
[releases_linux.json](https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json).
If you run Flutter as root, it prints the banner "trying to run flutter as
root". The banner is harmless.

`just frontend check` does not need Chrome or the Android SDK. The tests run
headless. Only a build for one platform needs the toolchain of that platform:

- Linux desktop (`flutter build linux`): `clang cmake ninja-build pkg-config
  libgtk-3-dev libsecret-1-dev`.
- Android: the Android SDK. See [CI and releases](ci-and-releases.md).

### `.env` files

There are two `.env` files. Different tools read them. Git ignores both.

| File | Copy from | Read by | Required |
|---|---|---|---|
| `.env` (repository root) | `.env.example` | `docker compose`, `just dev` | `POSTGRES_PASSWORD` (the containers do not start without it) |
| `backend/.env` | `backend/.env.example` | `just backend run` | Nothing. Every setting has a default. |

Next: [Running and testing](workflow.md).
