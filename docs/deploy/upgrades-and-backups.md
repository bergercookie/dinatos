# Upgrades and backups

Upgrade an instance, back it up, and restore it.

## Upgrade

1. Back up first (below).
2. Update and rebuild:

   ```bash
   git pull
   docker compose up -d --build
   ```

3. Check `docker compose logs backend`.

Migrations run automatically each time the app container starts. A failed migration shows in the logs, and the app does not start.

Prebuilt images are published at `ghcr.io/bergercookie/dinatos` (tags `latest` and each version). To use one, replace `build: .` and `image: dinatos:local` in `docker-compose.yml` with `image: ghcr.io/bergercookie/dinatos:latest`. Upgrade with `docker compose pull && docker compose up -d`.

## What to back up

All data is in `./data/postgres` (or `$DINATOS_DATA_DIR/postgres`), owned by `DINATOS_UID:DINATOS_GID` from your `.env` -- set them to your own user (`id -u`, `id -g`) and you can read and copy it without `sudo`. Prefer a dump over copying the live directory, so a restore works across Postgres versions; if you do copy it, stop the stack first.

### Moving from the old `dinatos-postgres-data` volume

Older versions kept the data in a named Docker volume. Dump it first (`pg_dump` below) while the old stack is still up, then `docker compose down --volumes`, `git pull`, set `DINATOS_UID`/`DINATOS_GID`, `docker compose up -d --wait postgres`, and restore the dump. The old volume's files are Postgres 16-alpine's (uid 70), so don't try to reuse them in place.

## Back up with `pg_dump`

```bash
docker compose exec postgres pg_dump -U dinatos dinatos > dinatos-backup.sql
```

Use your own `POSTGRES_USER` and `POSTGRES_DB` if you changed them. Dinatos has no built-in schedule. Run this from your own cron job.

## Restore with `psql`

Restore only onto an empty database: a fresh data directory, with the app having started once to run migrations.

```bash
docker compose up -d --wait postgres
docker compose exec -T postgres psql -U dinatos dinatos < dinatos-backup.sql
```

## Backup from the app (administrators)

**Settings -> Administration** has **Download full backup** and **Restore from backup**.

- The backup is one JSON file with every account, exercise, routine, activity, measurement, planned workout and import record. It works across Postgres versions.
- It contains **password hashes and stored WorkoutX API keys**. Keep it as private as the database.
- Restore **replaces everything on the server** in one step. An invalid file changes nothing.
- After a restore, everyone is logged out except you, and only if your account (same id and email) is in the backup. Otherwise log in with an account from the backup. Login sessions are not part of a backup.

Use `pg_dump` for scheduled backups. Use the in-app backup to move between instances or recover without shell access.

Each user can also export their own data. See [Exporting and importing your data](../user-guide/data-export.md).

## Destructive commands

| Command | Effect |
|---|---|
| `docker compose down` | Stops containers. **Keeps** data. |
| `docker compose down --volumes` | Keeps `./data` too. Delete `./data/postgres` to wipe the database. |
