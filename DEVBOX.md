# Devbox Development Environment

**Devbox is the recommended approach for Dinatos development.** It provides a reproducible, containerized development environment with all required tools pre-configured.

## Quick Start

### 1. Install Devbox

```bash
./tools/install-devbox.sh
```

Alternatively, install manually from [devbox.dev](https://www.devbox.dev):

```bash
curl -fsSL https://get.devbox.dev | bash
```

### 2. Enter the Development Environment

```bash
devbox shell
```

This activates an isolated shell with all development tools available:
- **Python 3.12** — backend runtime
- **uv** — Python package manager
- **just** — task runner (≥1.31, with module support)
- **Docker & Docker Compose** — for local Postgres and container workflows
- **Git** — version control and pre-commit hooks
- **Flutter SDK** — frontend development
- **CMake** — build tooling

### 3. Install Python Virtualenvs

Inside `devbox shell`:

```bash
just install
```

This runs `uv sync` for the backend (frontend virtualenv is Flutter-specific).

## Common Workflows

All commands below assume you're inside `devbox shell`:

| Task | Command |
|------|---------|
| **Install dependencies** | `just install` |
| **Run all checks** | `just check` |
| **Run backend tests** | `just backend test` |
| **Run backend with auto-reload** | `just backend run` |
| **Apply formatter & lint fixes** | `just backend fmt` |
| **Start Postgres & backend** | `just docker up` (then set up `.env`) |
| **View all tasks** | `just --list` |

See `AGENTS.md` for additional details about running without Docker, migrations, and architecture decisions.

## Why Devbox?

- **Isolation**: Development doesn't interfere with system Python or other projects
- **Reproducibility**: Everyone uses the same `devbox.lock` — no "works on my machine"
- **Containerization**: Optional nix-based builds; no heavyweight Docker for the dev loop
- **Easy onboarding**: New contributors run one command and get a complete environment
- **Just compatibility**: Devbox includes `just ≥1.31` with module support (unlike Ubuntu's `apt install just`)

## Exiting the Environment

Simply type `exit` or press `Ctrl+D` to leave `devbox shell`.

## Troubleshooting

### "Modules are currently unstable" error

This happens if `just` is older than 1.31. Devbox ensures a current version is used — verify you're inside `devbox shell`:

```bash
just --version  # Should show ≥1.31
```

### Docker inside devbox

If you need Docker (e.g., for `just docker up` or `just backend test-migrations`), ensure your host Docker daemon is running and accessible. Devbox exposes the host's Docker socket.

### Custom .env Files

Copy `.env.example` to `.env` (or `backend/.env`) and adjust as needed. `.env` files are Git-ignored and won't be committed.

```bash
# For docker-compose services
cp .env.example .env

# For backend-only settings
cp backend/.env.example backend/.env
```

Then run:

```bash
just docker up      # Starts Postgres + backend
just backend run    # Or run backend directly against your Postgres
```

See `AGENTS.md` for Postgres connection details.

## Documentation

- **AGENTS.md** — Architecture, why certain tools are required, container setup details
- **README.md** — Project overview
- **backend/justfile** — Backend-specific tasks
- **devbox.json** — This environment's tool versions and shell scripts
