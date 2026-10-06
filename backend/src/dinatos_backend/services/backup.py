"""Full server backup and restore (admin only), and the helpers the per-user
export (`services.user_export`) shares with it.

The document is generic over the table metadata: every column of every table
in `BACKED_UP_TABLES` is exported, so adding a *column* needs no change here.
Adding a *table* does -- `tests/services/test_backup_coverage.py` fails until
the new table is either listed in `BACKED_UP_TABLES` or in `EXCLUDED_TABLES`
with a reason.

Restore is validate-then-replace: the document is parsed and checked in full
(format, version, columns, types, primary keys, foreign keys) before the
database is touched; then every table is emptied and refilled with the
original primary keys inside one transaction, which rolls back whole if the
database rejects anything.
"""

import enum
import json
import math
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import Column, Table, delete, select, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.schema import ColumnDefault

import dinatos_backend.models  # noqa: F401  (registers every table on Base.metadata)
from dinatos_backend.models.auth_session import AuthSession
from dinatos_backend.models.base import Base
from dinatos_backend.models.user import User
from dinatos_backend.schemas.backup import (
    BACKUP_FORMAT,
    FORMAT_VERSION,
    BackupRestoreResult,
    FullBackup,
)

# Columns that existed in earlier versions and have since been dropped: a backup
# made back then still restores, the value simply isn't kept.
_REMOVED_COLUMNS: dict[str, set[str]] = {"activity_sets": {"rpe"}}

BACKED_UP_TABLES: tuple[str, ...] = (
    "users",
    "user_profile",
    "exercises",
    "exercise_muscles",
    "routines",
    "routine_exercises",
    "routine_sets",
    "activities",
    "activity_exercises",
    "activity_sets",
    "hevy_import_records",
    "body_measurements",
)

# Table name -> why a backup deliberately leaves it out.
EXCLUDED_TABLES: dict[str, str] = {
    "auth_sessions": (
        "Ephemeral logins: a session row is a live credential (its hash), so a backup "
        "file must not carry them, and restoring must not resurrect old logins. Everyone "
        "logs in again after a restore, except the calling admin -- see restore_backup."
    ),
}

_MAX_ERRORS = 20


class BackupInvalidError(Exception):
    """The document (or what the database made of it) cannot be restored.
    `problems` is a list of human-readable reasons, capped at `_MAX_ERRORS`.
    """

    def __init__(self, problems: list[str]) -> None:
        super().__init__("; ".join(problems))
        self.problems = problems


def normalize_utc(value: datetime) -> datetime:
    """Aware UTC, whatever the driver handed back: sqlite returns naive
    datetimes (they were stored as UTC), Postgres aware ones in any zone.
    """
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def backup_tables() -> list[Table]:
    """The backed-up tables, parents before children."""
    return [table for table in Base.metadata.sorted_tables if table.name in BACKED_UP_TABLES]


def _to_json(value: Any) -> Any:
    if isinstance(value, datetime):
        return normalize_utc(value).isoformat()
    if isinstance(value, enum.Enum):
        return value.value
    return value


async def export_backup(db: AsyncSession, app_version: str) -> FullBackup:
    tables: dict[str, list[dict[str, Any]]] = {}
    for table in backup_tables():
        result = await db.execute(select(table).order_by(*table.primary_key.columns))
        tables[table.name] = [
            {column.name: _to_json(row[column]) for column in table.columns}
            for row in result.mappings()
        ]
    return FullBackup(exported_at=datetime.now(UTC), app_version=app_version, tables=tables)


def _convert(column: Column[Any], value: Any) -> Any:
    """One JSON value to what the column stores, or `ValueError` saying why not."""
    if value is None:
        if not column.nullable:
            raise ValueError("must not be null")
        return None
    expected = column.type.python_type
    if issubclass(expected, enum.Enum):
        try:
            return expected(value)
        except ValueError:
            raise ValueError(f"{value!r} is not a valid {expected.__name__}") from None
    if expected is datetime:
        try:
            return normalize_utc(datetime.fromisoformat(value))
        except (TypeError, ValueError):
            raise ValueError(f"{value!r} is not an ISO 8601 timestamp") from None
    if isinstance(value, bool) != (expected is bool):
        raise ValueError(f"must be of type {expected.__name__}")
    if expected is float:
        if not isinstance(value, int | float) or not math.isfinite(value):
            raise ValueError("must be a finite number")
        return float(value)
    if not isinstance(value, expected):
        raise ValueError(f"must be of type {expected.__name__}")
    max_length = getattr(column.type, "length", None)
    if expected is str and max_length is not None and len(value) > max_length:
        raise ValueError(f"is longer than {max_length} characters")
    return value


def _parse_row(table: Table, raw: Any, problems: list[str], where: str) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        problems.append(f"{where}: must be an object")
        return None
    start = len(problems)
    for key in raw.keys() - table.columns.keys() - _REMOVED_COLUMNS.get(table.name, set()):
        problems.append(f"{where}: unknown column {key!r}")
    row: dict[str, Any] = {}
    for column in table.columns:
        if column.name not in raw:
            # A column added after this backup was made: fine if it can be
            # nullable or defaulted, otherwise the backup is unusable.
            if column.nullable:
                row[column.name] = None
            elif isinstance(column.default, ColumnDefault) and column.default.is_scalar:
                row[column.name] = column.default.arg
            else:
                problems.append(f"{where}: missing column {column.name!r}")
            continue
        try:
            row[column.name] = _convert(column, raw[column.name])
        except ValueError as error:
            problems.append(f"{where}: {column.name} {error}")
    return row if len(problems) == start else None


def _check_references(
    tables: list[Table], parsed: dict[str, list[dict[str, Any]]], problems: list[str]
) -> None:
    for table in tables:
        primary_key = table.primary_key.columns.keys()
        seen: set[tuple[Any, ...]] = set()
        for index, row in enumerate(parsed[table.name]):
            key = tuple(row[name] for name in primary_key)
            if key in seen:
                problems.append(f"{table.name}[{index}]: duplicate primary key {key}")
            seen.add(key)
        for foreign_key in table.foreign_keys:
            target = foreign_key.column
            known = {row[target.name] for row in parsed[target.table.name]}
            for index, row in enumerate(parsed[table.name]):
                value = row[foreign_key.parent.name]
                if value is not None and value not in known:
                    problems.append(
                        f"{table.name}[{index}]: {foreign_key.parent.name}={value} "
                        f"has no matching {target.table.name}.{target.name}"
                    )


def parse_backup(raw: bytes) -> dict[str, list[dict[str, Any]]]:
    """Validates a backup document completely and returns its rows, typed as
    the database wants them. Raises `BackupInvalidError` -- touching nothing --
    if any part of it is wrong.
    """
    try:
        document = json.loads(raw)
    except ValueError:  # includes UnicodeDecodeError
        raise BackupInvalidError(["the file is not valid JSON"]) from None
    if not isinstance(document, dict) or document.get("format") != BACKUP_FORMAT:
        raise BackupInvalidError([f"not a Dinatos backup (expected format {BACKUP_FORMAT!r})"])
    version = document.get("format_version")
    if version != FORMAT_VERSION or isinstance(version, bool):
        raise BackupInvalidError(
            [f"unsupported format_version {version!r}; this server reads {FORMAT_VERSION}"]
        )
    raw_tables = document.get("tables")
    if not isinstance(raw_tables, dict):
        raise BackupInvalidError(["'tables' must be an object"])

    problems: list[str] = []
    for name in sorted(raw_tables.keys() - set(BACKED_UP_TABLES)):
        problems.append(f"unknown table {name!r}")
    tables = backup_tables()
    parsed: dict[str, list[dict[str, Any]]] = {}
    for table in tables:
        rows = raw_tables.get(table.name)
        if not isinstance(rows, list):
            problems.append(f"table {table.name!r} is missing or not a list")
            continue
        before = len(problems)
        converted = [
            _parse_row(table, raw_row, problems, f"{table.name}[{index}]")
            for index, raw_row in enumerate(rows)
        ]
        if len(problems) == before:
            parsed[table.name] = [row for row in converted if row is not None]
    if not problems:
        _check_references(tables, parsed, problems)
        if not any(user["is_admin"] for user in parsed["users"]):
            problems.append("the backup contains no admin account; restoring it would lock you out")
    if problems:
        raise BackupInvalidError(problems[:_MAX_ERRORS])
    return parsed


def sequence_reset_statements(tables: list[Table]) -> list[str]:
    """Postgres: after inserting rows with explicit ids, each serial
    column's sequence still sits at its old value and the next ordinary
    insert would collide. Point each one just past the highest id present.
    `pg_get_serial_sequence` is NULL for a column with no sequence, which
    makes `setval` a no-op, so only real autoincrement keys are listed.
    """
    return [
        f"SELECT setval(pg_get_serial_sequence('{table.name}', '{column.name}'), "  # noqa: S608
        f"COALESCE(MAX({column.name}), 0) + 1, false) FROM {table.name}"
        for table in tables
        if (column := table.autoincrement_column) is not None
    ]


async def reset_sequences(db: AsyncSession) -> None:
    """Runs `sequence_reset_statements` -- on Postgres only; sqlite derives
    the next rowid from the table itself, so there is nothing to fix.
    """
    if db.get_bind().dialect.name != "postgresql":
        return
    for statement in sequence_reset_statements(Base.metadata.sorted_tables):
        await db.execute(text(statement))


async def restore_backup(
    db: AsyncSession, parsed: dict[str, list[dict[str, Any]]], caller: User, session: AuthSession
) -> BackupRestoreResult:
    """Replaces the entire server state with `parsed` (from `parse_backup`).

    Sessions are not in a backup, so every login is dropped -- except the
    caller's own current one, kept when the backup contains an account with
    the caller's id *and* email (the same person, so staying logged in is
    right; a recycled id for someone else must not inherit it). Otherwise the
    caller is logged out like everyone else, and their next request is a 401.
    """
    keep = any(
        user["id"] == caller.id and user["email"] == caller.email for user in parsed["users"]
    )
    kept_session = {
        column.name: getattr(session, column.key) for column in AuthSession.__table__.columns
    }
    try:
        for table in reversed(Base.metadata.sorted_tables):
            await db.execute(delete(table))
        for table in backup_tables():
            if parsed[table.name]:
                await db.execute(table.insert(), parsed[table.name])
        if keep:
            await db.execute(
                Base.metadata.tables[AuthSession.__tablename__].insert(), [kept_session]
            )
        await reset_sequences(db)
        await db.commit()
    except SQLAlchemyError as error:
        await db.rollback()
        raise BackupInvalidError(
            [f"the database rejected the backup: {error.__class__.__name__}"]
        ) from error
    return BackupRestoreResult(
        rows={name: len(rows) for name, rows in parsed.items()}, session_kept=keep
    )
