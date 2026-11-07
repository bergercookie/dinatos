# Contributing

Thank you for your help. This page shows you how to go from a clone to a
passing build. The pages in "Where to find more" give more detail.

## The project in one minute

- `backend/`: the Python API (FastAPI, SQLAlchemy, Postgres)
- `frontend/`: the Flutter app (web, Android, Linux)
- `mcp_server/`: the server that lets AI assistants read your data
- `docs/`: the documentation site
- `e2e/`, `screenshots/`: the browser tests and the README screenshots

## Where to find more

- [Environment setup](https://bergercookie.github.io/dinatos/development/environment-setup.html): install the tools
- [Running and testing](https://bergercookie.github.io/dinatos/development/workflow.html): run the app and the tests
- [CI and releases](https://bergercookie.github.io/dinatos/development/ci-and-releases.html): what runs on your PR, and how releases ship
- [Architecture](https://bergercookie.github.io/dinatos/architecture/index.html): why the code has this shape
- [AGENTS.md](https://github.com/bergercookie/dinatos/blob/main/AGENTS.md): environment pitfalls (written for coding agents, but useful for anyone)

## Set up

Every task is a [`just`](https://github.com/casey/just) recipe. To see all
recipes, run `just --list`.

You need Python 3.12, [`uv`](https://docs.astral.sh/uv/) and `just` 1.31 or
newer. The `just` package from Ubuntu's `apt` is too old.

To install the dependencies and run all checks, do these steps:

```bash
just install   # backend and tool dependencies
just check     # lint, tests, docs build: what CI runs
```

The tests use an in-memory database. You do not need Postgres.

To install everything with one command (Docker, Flutter and CMake also), use
[Devbox](https://www.jetify.com/devbox):
`./tools/install-devbox.sh && devbox shell`.
For a manual setup, see [environment setup](https://bergercookie.github.io/dinatos/development/environment-setup.html).

## Before you open a PR

Run `just check`. Then run more checks for the parts you changed:

| You changed | Also do | Needs |
|---|---|---|
| `frontend/` | Run `just frontend check` | Flutter SDK |
| `backend/alembic/versions/` | Run `just backend test-migrations` | Docker |
| Screens or navigation | Run `just e2e test` | Docker, Flutter SDK |
| How the screens look | Run `just screenshots generate`, then commit the result | Docker, Flutter SDK |
| A database table | Add the table to `BACKED_UP_TABLES` in `backend/src/dinatos_backend/services/backup.py` | |

Also follow these rules:

- Make one change in each PR.
- If users or operators can see your change, update the matching page in
  `docs/` in the same PR.
- CI adds a comment to your PR. The comment compares the test coverage of your
  branch with `main`.

## Bugs and ideas

To report a bug or suggest an idea, open an
[issue](https://github.com/bergercookie/dinatos/issues). For a large change,
open an issue first. Then we can agree on the approach.

Security problems: do not open an issue. Read
[SECURITY.md](https://github.com/bergercookie/dinatos/blob/main/SECURITY.md).
