# Domain model and repository layout

This page shows what Dinatos stores (users, exercises, routines, activities
and more). It also shows where the code is. Read this page first if you are
new to the code. The [backend](backend.md) and [frontend](frontend.md) pages
use these terms and do not define them again.

For the same model from the point of view of a user, see
[Concepts](../user-guide/concepts.md).

## Concepts

Each concept is a database table, or a small group of tables. The tables are
in `backend/src/dinatos_backend/models/`.

| Term | Meaning |
| --- | --- |
| **User** | A local account. Dinatos is a household app: many people share one server. Exactly one user owns each item, except exercises. |
| **Exercise** | One movement, for example "Romanian deadlift". It is the only global resource. All users share one catalog. |
| **Routine** | A saved template with a name. It is an ordered list of exercises. Each exercise has planned sets. |
| **Activity** | A recorded gym session. It has the exercises that the user did, with sets, reps and weights. It comes from a routine or from a workout that the user builds during the session. All stats use activities. |
| **Planned workout** | A routine or free-form session that has a date in the future. It has a duration and a reminder lead time. It is one calendar entry. |
| **Superset** | Exercises that the user does back-to-back. Consecutive exercises with the same `superset_group` number form a superset. This applies to routines and activities. When a user starts a workout from a routine, the app copies the groups. |
| **Set** | One row of weight, reps, distance and duration in a routine exercise or activity exercise. It has a `set_type`, for example warm-up. A warm-up never counts toward records. Only a `completed` set counts toward records, history and totals. |

### Exercises: built-in and custom

- `Exercise.is_custom=False` marks the catalog that Dinatos ships. A new
  instance seeds it. It cannot change: `PATCH` and `DELETE` return 403. This
  protects the routines and tutorials that refer to the catalog.
- `is_custom=True` is the default. It marks an exercise that a user created.
  A user can edit and delete it.

### Planned workouts are not activities

A plan must not count in stats before the user does the workout. When the user
saves a workout that started from a plan, the backend sets the
`completed_activity_id` of the plan to the new activity.

Planned workouts appear in the calendar on Home. They cause reminders on
Android. The backend also publishes them as an ICS feed. See
[Calendar feed](backend.md#calendar-feed).

### Tables at a glance

| Table | Purpose |
| --- | --- |
| `users`, `user_profile` | Accounts. One row of settings for each user |
| `auth_sessions`, `api_keys` | Logins and API keys (see [Authentication](backend.md#authentication)) |
| `exercises`, `exercise_muscles` | The shared catalog |
| `routines`, `routine_exercises`, `routine_sets` | Templates |
| `activities`, `activity_exercises`, `activity_sets` | Sessions that the user did |
| `planned_workouts` | Calendar entries |
| `body_measurements` | Weigh-ins and tape measurements, with dates |
| `hevy_import_records`, `intervals_imported_activities` | Duplicate tracking for imports |

> [!NOTE]
> When you add a table, you must also register it for backup. See
> [Backup and data export](backend.md#backup-and-data-export).

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

The root `Dockerfile` and `docker-compose.yml` build and run all parts
together.

Each package directory has its own `justfile`. It does not need the other
packages (`cd backend && just test`). The root `justfile` imports each one as
a `just` module. For this reason, `just backend test` works from anywhere in
the repository.

The backend code has layers in `backend/src/dinatos_backend/`:

| Directory | Contents |
| --- | --- |
| `models/` | SQLAlchemy tables |
| `schemas/` | pydantic request and response shapes |
| `services/` | Business logic |
| `api/` | FastAPI routers (`api/routers/`) and dependencies (`api/deps.py`) |

## Module boundaries

`backend/tach.toml` declares which layer can import which other layer.
`just check` and CI enforce it. The imports go in one direction:

```text
config / models -> schemas -> db -> services -> api -> app (main.py)
```

If your change needs a new arrow, think again about the change first.
