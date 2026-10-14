# Contributing

Thanks for helping. This page gets you from clone to a passing build; the
[development docs](https://bergercookie.github.io/dinatos/development/index.html)
go deeper.

## The project in one minute

- `backend/`: Python API (FastAPI, SQLAlchemy, Postgres)
- `frontend/`: Flutter app (web, Android, Linux)
- `mcp_server/`: lets AI assistants read your data
- `docs/`: the documentation site
- `e2e/`, `screenshots/`: browser tests and README screenshots

## Set up

Every task is a [`just`](https://github.com/casey/just) recipe. Run `just --list`
to see them all.

You need Python 3.12, [`uv`](https://docs.astral.sh/uv/) and `just` 1.31 or newer.
(Ubuntu's `apt install just` is too old.)

```bash
just install   # backend and tool dependencies
just check     # lint, tests, docs build: what CI runs
```

The tests use an in-memory database, so no Postgres is needed.

Prefer one command that installs everything (Docker, Flutter, CMake too)?
Use [Devbox](https://www.jetify.com/devbox):
`./tools/install-devbox.sh && devbox shell`.
Manual setup is in [environment setup](https://bergercookie.github.io/dinatos/development/environment-setup.html).

## Before you open a PR

Run `just check`. Then, depending on what you changed:

| You changed | Also run | Needs |
|---|---|---|
| `frontend/` | `just frontend check` | Flutter SDK |
| `backend/alembic/versions/` | `just backend test-migrations` | Docker |
| screens or navigation | `just e2e test` | Docker, Flutter |
| what the screens look like | `just screenshots generate`, commit the result | Docker, Flutter |
| a database table | add it to `BACKED_UP_TABLES` in `backend/src/dinatos_backend/services/backup.py` | |

Also:

- Keep a PR to one change.
- If users or operators will notice the change, update the matching page in
  `docs/` in the same PR.
- CI comments the test coverage of your branch against `main` on your PR.

## Bugs and ideas

Open an [issue](https://github.com/bergercookie/dinatos/issues). For a
larger change, open one first so we can agree on the approach.

Security problems: do not open an issue, see [SECURITY.md](https://github.com/bergercookie/dinatos/blob/main/SECURITY.md).

## Where things are documented

- [Development docs](https://bergercookie.github.io/dinatos/development/index.html): workflow, CI, releases
- [Architecture](https://bergercookie.github.io/dinatos/architecture/index.html): why the code is shaped this way
- [AGENTS.md](https://github.com/bergercookie/dinatos/blob/main/AGENTS.md): environment pitfalls (written for coding agents, useful for anyone)
