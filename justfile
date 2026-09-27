# Task runner for Dinatos. `just` on its own lists everything.
#
# Recipes live in the directory they operate on, as a plain, self-sufficient
# `justfile` you can also run directly (`cd backend && just test`). This file
# imports each one as a module so `just <module> <recipe>` works from
# anywhere in the repo too.
set shell := ["bash", "-euo", "pipefail", "-c"]
# Loads .env into every recipe's own environment (not just docker compose's
# separate reading of it) -- `dev` below needs POSTGRES_USER/PASSWORD/DB
# from it to build DINATOS_DATABASE_URL for the backend it runs directly on
# the host, and DINATOS_ADMIN_EMAIL/PASSWORD just flow through as-is since
# they're already named right.
set dotenv-load := true
set dotenv-filename := ".env"

default:
    @just --list

mod backend 'backend/justfile'
mod docker 'docker/justfile'
mod docs 'docs/justfile'
mod frontend 'frontend/justfile'
mod packaging 'packaging/justfile'
mod screenshots 'screenshots/justfile'

# ---------------------------------------------------------------- whole repo

# Set up every package's virtualenv.
install: backend::install

# Everything CI runs for the backend and docs (not the frontend -- see AGENTS.md).
check: lint backend::test docs::docs

# Every pre-commit hook over the whole tree: ruff, mypy, tach, file hygiene.
lint:
    uvx pre-commit run --all-files

# Install the git pre-commit hooks.
hooks:
    uvx pre-commit install

# ------------------------------------------------------------ development

# Run Postgres, the backend, and the frontend together -- the fastest path to a working app in a browser (needs .env; see .env.example).
dev:
    #!/usr/bin/env bash
    # A shebang, not the usual plain recipe body: `just` otherwise runs
    # each line of a recipe as its *own* separate shell invocation, so
    # `export`, `$!` and `trap` here wouldn't survive from one line to the
    # next -- this makes the whole recipe one real script/one real shell.
    #
    # Ctrl+C stops the backend and frontend; Postgres itself keeps running,
    # same as after `just docker up` -- `just docker down` to stop it
    # without deleting its data, or `just dev-clean` to remove it entirely.
    set -euo pipefail
    docker compose up -d --wait postgres
    export DINATOS_DATABASE_URL="postgresql+asyncpg://${POSTGRES_USER:-dinatos}:${POSTGRES_PASSWORD:?set this in .env}@localhost:5432/${POSTGRES_DB:-dinatos}"
    cd backend && uv run alembic upgrade head
    uv run dinatos-backend &
    backend_pid=$!
    trap 'kill "$backend_pid" 2>/dev/null' EXIT
    echo "Backend:  http://127.0.0.1:8000"
    echo "Frontend: http://127.0.0.1:8081 (open this)"
    cd ../frontend && flutter pub get && flutter run -d web-server --web-port 8081

# Remove local backend containers/network and permanently delete the Postgres data volume.
dev-clean:
    docker compose down --volumes --remove-orphans
