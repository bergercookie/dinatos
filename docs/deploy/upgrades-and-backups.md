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

## What's destructive

- `docker compose down` -- stops the containers, **keeps** the data volume.
  Safe to run any time.
- `docker compose down --volumes` (`just dev-clean`, for the dev compose
  setup) -- removes the data volume permanently, along with the containers
  and network. Anything not backed up per the above is gone.

There's currently no built-in scheduled-backup mechanism -- the `pg_dump`
above run on a cron of your own choosing is the whole story.
