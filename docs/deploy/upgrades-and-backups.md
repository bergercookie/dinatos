# Upgrades and backups

This page shows how to upgrade a Dinatos instance, back it up and restore it.

## Upgrade

1. Make a backup. See [Back up with `pg_dump`](#back-up-with-pg_dump).
2. Get the new code and rebuild:

   ```bash
   git pull
   docker compose up -d --build
   ```

3. Read the logs for errors:

   ```bash
   docker compose logs backend
   ```

Migrations run automatically each time the app container starts. If a migration fails, the logs show the error and the app does not start.

### Use a prebuilt image

Dinatos publishes prebuilt images at `ghcr.io/bergercookie/dinatos`. The tags are `latest` and each version.

1. In `docker-compose.yml`, replace `build: .` and `image: dinatos:local` with `image: ghcr.io/bergercookie/dinatos:latest`.
2. To upgrade, run:

   ```bash
   docker compose pull && docker compose up -d
   ```

## What to back up

All data is in `./data/postgres`, or in `$DINATOS_DATA_DIR/postgres`. The owner is `DINATOS_UID:DINATOS_GID` from your `.env`. If you set them to your own user (`id -u`, `id -g`), you can read and copy the data without `sudo`.

Use a dump, not a copy of the live directory. A dump restores across Postgres versions. If you copy the directory, stop the containers first.

## Back up with `pg_dump`

```bash
docker compose exec postgres pg_dump -U dinatos dinatos > dinatos-backup.sql
```

If you changed `POSTGRES_USER` or `POSTGRES_DB`, use your own values. Dinatos has no built-in backup schedule. To make backups regularly, run this command from your own cron job.

## Restore with `psql`

> [!WARNING]
> Restore only onto an empty database. Use a new data directory, and start the app one time to run the migrations.

```bash
docker compose up -d --wait postgres
docker compose exec -T postgres psql -U dinatos dinatos < dinatos-backup.sql
```

## Back up from the app (administrators)

**Settings -> Administration** has the buttons **Download full backup** and **Restore from backup**.

The backup is one JSON file. It contains every account, exercise, routine, activity, measurement, planned workout and import record. It works across Postgres versions.

> [!WARNING]
> The backup file contains password hashes and stored WorkoutX API keys. Keep it as private as the database.
>
> A restore replaces everything on the server in one step. If the file is not valid, nothing changes.

After a restore, these rules apply:

- Dinatos logs out all users, except you. You stay logged in only if your account (same id and same email) is in the backup.
- If your account is not in the backup, log in with an account from the backup.
- A backup does not contain login sessions.

Use `pg_dump` for scheduled backups. Use the in-app backup to move to another instance, or to recover when you have no shell access.

Each user can also export their own data. See [Exporting and importing your data](../user-guide/data-export.md).

## Destructive commands

| Command | Effect |
|---|---|
| `docker compose down` | Stops the containers. **Keeps** the data. |
| `docker compose down --volumes` | Does not delete `./data`. To delete the database, delete `./data/postgres`. |
