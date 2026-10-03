# Contributing to Dinatos

Thanks for looking at contributing code. This page is the human-facing front
door; `AGENTS.md` covers the same ground for a coding agent working
unattended in a fresh container, and `docs/development/` (rendered as part
of the Sphinx site, but readable in place too) goes into more depth than
either.

## Devbox + `just` is the interface to this repo

Don't reach for `uv run ...`, `flutter ...`, or `docker compose ...` by hand.
Every task -- installing dependencies, linting, testing, running the app,
building the docs, cutting a packaged release -- is a `just` recipe, and
`just --list` (or `just` on its own) is always the up-to-date list of what's
available. That's a deliberate choice, not a style preference: a recipe is
documentation that can't drift out of sync with what actually runs, the way
a paragraph of prose describing the same command can. If you find yourself
about to run a raw tool invocation because there's no recipe for it yet, add
the recipe instead of working around its absence.

[Devbox](https://www.jetify.com/devbox) is the recommended way to get every tool a
recipe might need (Python 3.12, `uv`, a current `just`, Docker, the Flutter
SDK, CMake) onto your `PATH` without touching your system install of any of
them:

```bash
./tools/install-devbox.sh   # installs Devbox itself if missing, then `devbox install`
devbox shell                 # enters the pinned environment
just install                 # backend virtualenv
just check                   # lint, backend tests, docs build -- what CI runs
```

See `docs/development/environment-setup.md` for the non-Devbox path (plain
`apt`/manual installs), and for exactly why Ubuntu's own `apt install just`
doesn't work here (it's old enough to reject this repo's `mod`-based root
`justfile` outright -- see `AGENTS.md`).

## Before opening a PR

- `just check` must pass -- it's the same lint/test/docs gate CI's `check`
  job runs (pre-commit over the whole tree: ruff, `mypy --strict`, `tach`'s
  module-boundary check, `hadolint` on the root `Dockerfile`, plus file
  hygiene hooks -- see `.pre-commit-config.yaml`; then the backend test
  suite; then a Sphinx docs build with warnings as errors).
- Touched anything under `backend/alembic/versions/`? Also run
  `just backend test-migrations` (CI's `migrations` job) -- needs Docker; a
  sqlite-backed unit test structurally can't catch a Postgres-specific
  migration bug (see `AGENTS.md`).
- Touched `frontend/`? Also run `just frontend check` (CI's `frontend` job)
  -- needs a real Flutter SDK, which is why it's a separate recipe/job from
  the root `just check` rather than folded into it.
- Touched anything the app's screens render (a model's shape, a screen's
  layout)? `just screenshots generate` regenerates
  `README.md`'s screenshots against a real backend + frontend build; commit
  the result. (Not checked in CI: pixel output differs between machines.)
- Touched the first-run tour, or navigation/screens it points at? `just e2e
  test` (CI's `e2e` job) drives the real web build in a real browser,
  against a real backend and Postgres, and walks a new account through
  it -- the one layer neither `flutter test` (mocked API) nor the backend's
  suite (no UI) covers. Needs Docker and the Flutter SDK, like `screenshots`.
- Keep each PR to one logical change. If it changes user-visible or
  operator-visible behavior, update the matching docs section in the same
  PR -- `docs/user-guide/` for what an end user sees, `docs/deploy/` for
  what a self-hosting operator needs to know, `docs/architecture/` for why
  it's built the way it is. A behavior change with no doc update is treated
  as an incomplete PR, not a follow-up someone else owes.

## Reporting bugs / proposing changes

Security vulnerabilities are the exception: don't open a public issue, follow
[`SECURITY.md`](https://github.com/bergercookie/dinatos/blob/main/SECURITY.md) instead.

Open a GitHub issue or PR against `main`. For anything beyond a small fix,
opening an issue first to agree on the approach saves a rewritten PR later
-- especially for anything touching the domain model or the API surface,
where `docs/architecture/backend.md` explains the reasoning behind the
current design (worth reading before proposing to change it).

## Where things are documented

- **`AGENTS.md`** -- environment gotchas and non-obvious failure modes
  (the `just` version trap, the Dockerfile's `--no-editable` requirement,
  the coverage/`greenlet` interaction, why Alembic's config lives in
  `pyproject.toml`). Read this first if something that should work doesn't.
- **`docs/development/`** -- the full contributor workflow: environment
  setup (Devbox and manual), running and testing each piece, what CI does
  and how to reproduce it locally, cutting a release.
- **`docs/architecture/`** -- the domain model, the backend and frontend's
  internal design and the reasoning behind it, and how release artifacts
  are built.
- **`docs/user-guide/`** and **`docs/deploy/`** -- not aimed at
  contributors, but worth skimming: they're the spec for what a change
  should look like from an app user's or a self-hosting operator's side.
