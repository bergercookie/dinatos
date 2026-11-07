# Environment setup

> [!TIP]
> Always install [`devbox`](https://www.jetify.com/devbox) and
> [`just`](https://just.systems/man/en/) first. We use `devbox` to install all
> the project dependencies and set up a shell that's suitable for development
> and we use `just` as the source of truth and the main point of interaction
> with everything in this repository.

Every task in this repository is a [`just`](https://github.com/casey/just)
recipe. To see all recipes, run `just --list`. To run a recipe from the
`justfile` of a subdirectory, use `just <module> <recipe>`. For example, run
`just backend test`.

## Devbox (recommended)

[Devbox](https://www.jetify.com/devbox) installs the tools in an isolated
shell. It does not change the packages of your system. `devbox.json` lists
them: Python 3.12, `uv`, `just`, Flutter (with Dart), CMake and Git.

```bash
./tools/install-devbox.sh   # installs Devbox if missing, then `devbox install`
devbox shell
just install
just check
```

- `devbox.json` pins `python@3.12`. The other tools use `@latest`. If a
  recipe fails only inside `devbox shell`, run `devbox update`.
- If you see the error "Modules are currently unstable", you are not in the
  Devbox shell, or your `just` is too old. To check, run `just --version`.

## What Devbox does not install

Install these items yourself, and only when you need them. `just check` needs
none of them: the backend tests use in-memory SQLite, and the Flutter tests run
headless, without Chrome or the Android SDK.

| Item | Needed for | How to get it |
|---|---|---|
| Docker (the daemon) | `just dev`, `just docker up`, `just backend test-migrations`, `just e2e test`, `just screenshots generate`, `just trivy` | Install Docker on your host. Devbox uses the daemon of the host. If `docker ps` cannot connect, start the daemon. Do not assume that Docker is missing. |
| Chromium for Playwright | `just e2e test`, `just screenshots generate` | Run `just e2e install` (or `just screenshots install`). It downloads the browser. |
| Android SDK and a JDK (17 or newer) | `just packaging build-apk`, `just android ...` | Run `./tools/install-android-sdk.sh` for the SDK. Install a JDK with your package manager. The emulator (`just android emulator`) also needs KVM (`/dev/kvm`). |
| Linux desktop build libraries | `flutter build linux`, `just packaging build-deb` and `build-appimage` | Install `clang ninja-build pkg-config libgtk-3-dev libsecret-1-dev` with `apt`. Or use the `*-docker` recipes, which need only Docker. See [Releases and packaging](releases.md#linux-desktop-target). |

To start the Docker daemon by hand:

```bash
sudo dockerd > /tmp/dockerd.log 2>&1 &
```

## Manual setup

Use this section only if you do not use Devbox.

### `just` 1.31 or newer

The root `justfile` loads the `justfile` of each package with `mod`. Before
`just` 1.31, `mod` was unstable.

> [!WARNING]
> The `just` package from Ubuntu's `apt` is version 1.21. It fails with the
> error "Modules are currently unstable".

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

### Python, `uv` and Flutter

Install Python 3.12, [`uv`](https://docs.astral.sh/uv/) and the
[Flutter SDK](https://docs.flutter.dev/get-started/install/linux). No `apt`
package has the Flutter SDK. Then run these recipes:

```bash
just install   # backend and MCP server virtualenvs (uv sync)
just check     # lint, tests, docs build
```

### `.env` files

Two `.env` files exist. Different tools read them. Git ignores both.

| File | Copy from | Read by | Required |
|---|---|---|---|
| `.env` (repository root) | `.env.example` | `docker compose`, `just dev` | `POSTGRES_PASSWORD` (the containers do not start without it) |
| `backend/.env` | `backend/.env.example` | `just backend run` | Nothing. Every setting has a default. |

Next: [Running and testing](workflow.md).
