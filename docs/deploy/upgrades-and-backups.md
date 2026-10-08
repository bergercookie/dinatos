# Upgrades and backups

## Upgrading

```bash
docker compose pull   # or rebuild, if you're building the image yourself
docker compose up -d
```

Database migrations run automatically every time the backend container
starts (`docker-entrypoint.sh`: `alembic upgrade head`, then the server
process itself) -- there's no separate migration step to remember. A
backend that fails to start after an upgrade is worth checking
`docker compose logs backend` for before anything else; a migration
failure surfaces there, not as a silent no-op.

> **Note:** back up first (below) if the version you're upgrading past has
> a migration you can't easily reason about -- `alembic downgrade` exists,
> but reaching for a backup is simpler than reasoning about a specific
> migration's `downgrade()` under pressure.

## Backups

All persistent state lives in one place: the `dinatos-postgres-data` Docker
volume (`docker-compose.yml`). Back it up by dumping the database itself,
not the raw volume files, so a restore works even across a Postgres version
bump:

```bash
docker compose exec postgres pg_dump -U dinatos dinatos > dinatos-backup.sql
```

(Substitute your own `POSTGRES_USER`/`POSTGRES_DB` if you changed them from
the `.env.example` defaults.) Restoring onto a fresh instance:

```bash
docker compose up -d --wait postgres
cat dinatos-backup.sql | docker compose exec -T postgres psql -U dinatos dinatos
```

Restore onto a database that's actually empty (a fresh volume, migrations
already applied by the backend's own startup, no rows yet) -- `psql` isn't
going to reconcile a restore against existing data for you.

### From the app (admins)

**Settings -> Administration** has **Download full backup** and **Restore from
backup** (also `GET /admin/backup` and `POST /admin/backup/restore`). The
backup is one JSON file with every account, exercise, routine, activity,
measurement and Hevy/Intervals.icu import record. It is independent of the Postgres version
and of ids, but it also contains **password hashes and any stored WorkoutX API
keys**: keep it as private as the database itself.

Restoring **replaces everything on the server** in one transaction (an
invalid file changes nothing). Everyone is logged out afterwards except you,
and only if your account (same id and email) is in the backup; otherwise you
log in again with an account from it. Login sessions are not part of a backup.
`pg_dump` above remains the better tool for scheduled, whole-database backups;
this one is for moving between instances or recovering from a mistake without
shell access.

Every user can also export or import just their own data from **Settings ->
Data** -- see [Exporting and importing your data](../user-guide/data-export.md).

## What's destructive

- `docker compose down` -- stops the containers, **keeps** the data volume.
  Safe to run any time.
- `docker compose down --volumes` (`just dev-clean`, for the dev compose
  setup) -- removes the data volume permanently, along with the containers
  and network. Anything not backed up per the above is gone.

There's currently no built-in scheduled-backup mechanism -- the `pg_dump`
above run on a cron of your own choosing is the whole story.
