# Environment setup

How to install the tools you need to build and test Dinatos. Use Devbox
for one-command setup, or install tools by hand. For the shortest path
(Python, `uv`, `just`), see [Contributing](contributing.md).

Every task in this repo is a [`just`](https://github.com/casey/just) recipe.
`just --list` shows them all; `just <module> <recipe>` runs one from a
subdirectory's own `justfile` (e.g. `just backend test`).

## What needs what

| You want to run | You need |
|---|---|
| `just install`, `just check` | Python 3.12, `uv`, `just` 1.31+ |
| `just backend test-migrations`, `just e2e test`, `just dev`, `just docker up` | Docker |
| `just frontend check`, `just e2e test`, `just screenshots generate` | Flutter SDK |

`just check` needs no database: the backend tests use in-memory sqlite.

## Devbox (recommended)

[Devbox](https://www.jetify.com/devbox) installs Python 3.12, `uv`, `just`,
Flutter, CMake and Git into an isolated shell. It does not touch your system
packages.

```bash
./tools/install-devbox.sh   # installs Devbox if missing, then `devbox install`
devbox shell
just install
just check
```

- `devbox.json` pins `python@3.12`. The other tools float at `@latest`. If a
  recipe fails only inside `devbox shell`, run `devbox update` first.
- Devbox does not provide a Docker daemon. It uses your host's, so Docker
  must be running on the host.
- A "Modules are currently unstable" error means you are not in the shell, or
  your `just` is too old. Check with `just --version`.

## Manual setup

### `just` 1.31 or newer

The root `justfile` loads each package's `justfile` with `mod`, which was
unstable before `just` 1.31. Ubuntu's `apt install just` ships 1.21 and fails
with "Modules are currently unstable". Do not work around it with `--unstable`
or `JUST_UNSTABLE=1`. Install a current build:

```bash
cargo install just --locked
```

Or use the [install script](https://github.com/casey/just#installation). If
the script is blocked (403) by a sandbox proxy, download a release tarball
from GitHub directly (1.43.0 works):

```bash
V=1.43.0
curl -sSfL "https://github.com/casey/just/releases/download/$V/just-$V-x86_64-unknown-linux-musl.tar.gz" \
    | tar -xzf - -C /usr/local/bin just
```

### Python and `uv`

```bash
just install   # backend and MCP server virtualenvs (uv sync)
just check     # lint, tests, docs build
```

### Docker

Needed wherever the table above says so. If `docker ps` cannot connect to the
daemon, start it instead of assuming Docker is missing:

```bash
sudo dockerd > /tmp/dockerd.log 2>&1 &
```

### Flutter SDK

`frontend/` needs a real Flutter SDK on `PATH`. There is no apt package.

```bash
curl -o /tmp/flutter.tar.xz \
    https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_<version>-stable.tar.xz
tar -xf /tmp/flutter.tar.xz -C /opt   # -> /opt/flutter/bin/flutter
export PATH="/opt/flutter/bin:$PATH"
git config --global --add safe.directory /opt/flutter   # else "dubious ownership"
flutter config --no-analytics && dart --disable-analytics
```

Find the current `<version>` in
[releases_linux.json](https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json).
Running as root prints a harmless "trying to run flutter as root" banner.

`just frontend check` needs neither Chrome nor the Android SDK; tests run
headless. Only building for a specific platform needs that platform's
toolchain:

- Linux desktop (`flutter build linux`): `clang cmake ninja-build pkg-config
  libgtk-3-dev libsecret-1-dev`.
- Android: the Android SDK. See [CI and releases](ci-and-releases.md).

### `.env` files

Two files, read by different things. Both are git-ignored.

| File | Copy from | Read by | Required |
|---|---|---|---|
| `.env` (repo root) | `.env.example` | `docker compose`, `just dev` | `POSTGRES_PASSWORD` (containers refuse to start without it) |
| `backend/.env` | `backend/.env.example` | `just backend run` | Nothing; every setting has a default |

Next: [Running and testing](workflow.md).
