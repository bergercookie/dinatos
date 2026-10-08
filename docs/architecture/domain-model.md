# Domain model and repository layout

## Concepts

- **users** -- local accounts, first-class from the start: this is a
  household app, not a single-user one. `exercises` are the one thing shared
  across every account; everything else belongs to exactly one.
- **exercises** -- e.g. Romanian deadlift. The shipped catalog
  (`Exercise.is_custom=False`) is immutable -- a widely-agreed-upon staple
  set every instance starts with, never editable or deletable, so the
  catalog someone's routines and tutorials reference can't be pulled out
  from under them. Anything a user adds themselves is a custom exercise
  (`is_custom=True`, the default) and is fully theirs to edit or delete.
- **routines** -- a named list of exercises, e.g. an upper-body routine.
- **activities** -- a recorded gym session: a list of completed exercises
  with their sets, reps, weights. An activity can come
  from running a saved routine, or from an ephemeral one built on the spot.
- **planned workouts** -- a routine (or free-form session) scheduled for a
  future time: one calendar entry. Not an activity -- it only becomes one when a
  workout started from it is saved, which links the two
  (`completed_activity_id`). Shown on Home's calendar, reminded on Android, and
  published as an ICS feed.
- **supersets** -- consecutive exercises sharing a `superset_group`, on a
  routine's exercises and an activity's alike; starting a workout from a
  routine carries them over.

(See [Concepts](../user-guide/concepts.md) for the same model explained for
someone using the app rather than changing its code.)

## Repository layout

```text
dinatos/
  backend/   FastAPI + async SQLAlchemy + pydantic API, backed by Postgres
  frontend/  Flutter app (web today; the same codebase targets Android)
  docs/      This site (Markdown, rendered with Sphinx + MyST)
```

Each package directory owns a plain, self-sufficient `justfile`
(runnable directly with `cd backend && just test`); the root `justfile`
imports each one as a module with `mod`, so `just backend test` works from
anywhere in the repo too.

## Build order

The parts don't get built in parallel: a client built before the domain
model settles would just end up chasing it. Instead:

1. **Tooling skeleton** -- justfiles, pre-commit (ruff, mypy, tach, pytest),
   an empty FastAPI app with a health check, CI running `just check`.
   *(done)*
2. **Backend core** -- exercises, routines, activities and settings: full
   CRUD over Postgres via async SQLAlchemy, with the test suite as the spec.
   *(done -- see [Backend](backend.md#api-surface))*
3. **Hevy import** -- backend-only work that stress-tests the schema against
   real exported data before anything else depends on it. *(done, verified
   against a real export -- see [Backend](backend.md#hevy-import))*
4. **Flutter frontend** against the now-stable API -- this is where the
   domain model actually gets validated.
   *(done: exercises, routines, activities, profile and measurements all
   have working screens against the real API -- see [Frontend](frontend.md))*
   *(current stage)*

## Module boundaries

`tach.toml` in each Python package enforces a one-way dependency graph
(e.g. `models -> services -> api`, never the reverse), checked by
`just check`/CI as part of the pre-commit suite. It starts nearly empty and
fills in as each layer is added, rather than being written speculatively
ahead of code that doesn't exist yet.
