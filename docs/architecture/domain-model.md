# Domain model and repository layout

What Dinatos stores (users, exercises, routines, activities, ...) and where
the code lives. Read this first if you are new to the codebase: the
[backend](backend.md) and [frontend](frontend.md) pages use these terms
without redefining them.

For the same model from a user's point of view, see
[Concepts](../user-guide/concepts.md).

## Concepts

Each concept is a database table (or a small group of them) in
`backend/src/dinatos_backend/models/`.

| Term | Meaning |
| --- | --- |
| **User** | A local account. Dinatos is a household app: several people share one server. Everything is owned by exactly one user, except exercises. |
| **Exercise** | One movement, e.g. "Romanian deadlift". The only global resource: all users share one catalog. |
| **Routine** | A saved, named template: an ordered list of exercises, each with planned sets. |
| **Activity** | A recorded gym session: the exercises actually done, with sets, reps and weights. It comes from running a routine or from a workout built on the spot. Activities feed all stats. |
| **Planned workout** | A routine (or free-form session) scheduled for a future time, with a duration and a reminder lead time. One calendar entry. |
| **Superset** | Exercises done back-to-back. Marked by giving consecutive exercises the same `superset_group` number, on routines and activities alike. Starting a workout from a routine copies the groups. |
| **Set** | One row of weight, reps, distance and duration inside a routine or activity exercise. It has a `set_type` (e.g. warm-up; warm-ups never count towards records). Only `completed` sets count towards records, history and totals. |

### Exercises: built-in vs custom

- `Exercise.is_custom=False` marks the shipped catalog. It is seeded on a new
  instance and is immutable: `PATCH` and `DELETE` return 403. This stops the
  catalog that routines and tutorials reference from changing underneath them.
- `is_custom=True` (the default) marks an exercise a user created. It can be
  edited and deleted.

### Planned workouts are not activities

A plan must not count in stats until it has been performed. When a workout
started from a plan is saved, the plan's `completed_activity_id` is set to
the new activity.

Planned workouts appear on Home's calendar, trigger reminders on Android, and
are published as an ICS feed (see [Calendar feed](backend.md#calendar-feed)).

### Tables at a glance

| Table | Purpose |
| --- | --- |
| `users`, `user_profile` | Accounts; one settings row per user |
| `auth_sessions`, `api_keys` | Logins and API keys (see [Authentication](backend.md#authentication)) |
| `exercises`, `exercise_muscles` | The shared catalog |
| `routines`, `routine_exercises`, `routine_sets` | Templates |
| `activities`, `activity_exercises`, `activity_sets` | Performed sessions |
| `planned_workouts` | Calendar entries |
| `body_measurements` | Dated weigh-ins and tape measurements |
| `hevy_import_records`, `intervals_imported_activities` | Duplicate tracking for imports |

Adding a table has a required extra step: register it for backup (see
[Backup and data export](backend.md#backup-and-data-export)).

## Repository layout

```text
dinatos/
  backend/      FastAPI + async SQLAlchemy + pydantic API, backed by Postgres
  frontend/     Flutter app (web and Android; Linux desktop packages too)
  mcp_server/   Small stdio proxy to the backend's MCP endpoint
  e2e/          Browser tests (Playwright) against the real web build
  docs/         This site (Markdown, rendered with Sphinx + MyST)
  packaging/    Linux .deb / AppImage packaging
```

The root `Dockerfile` and `docker-compose.yml` build and run everything
together.

Each package directory has its own self-sufficient `justfile`
(`cd backend && just test`). The root `justfile` imports each one as a `just`
module, so `just backend test` works from anywhere in the repo.

Backend code is layered under `backend/src/dinatos_backend/`:

| Directory | Holds |
| --- | --- |
| `models/` | SQLAlchemy tables |
| `schemas/` | pydantic request/response shapes |
| `services/` | Business logic |
| `api/` | FastAPI routers (`api/routers/`) and dependencies (`api/deps.py`) |

## Module boundaries

`backend/tach.toml` declares which layers may import which, and `just check`
(and CI) enforces it. The flow is one-way:

```text
config / models -> schemas -> db -> services -> api -> app (main.py)
```

If your change needs a new arrow, rethink the change first.
