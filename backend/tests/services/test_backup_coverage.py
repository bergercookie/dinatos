"""Guards that the full backup cannot silently fall behind the schema, plus
the Postgres-only sequence fix-up (which sqlite never runs).
"""

from types import SimpleNamespace
from typing import Any, cast

from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.models.base import Base
from dinatos_backend.services.backup import (
    BACKED_UP_TABLES,
    EXCLUDED_TABLES,
    backup_tables,
    reset_sequences,
    sequence_reset_statements,
)


def test_every_model_table_is_backed_up_or_explicitly_excluded() -> None:
    """If this fails you added (or renamed) a table: add it to
    `BACKED_UP_TABLES` in `services/backup.py` -- or, if it is really
    ephemeral, to `EXCLUDED_TABLES` with the reason. Columns need no action.
    """
    model_tables = set(Base.metadata.tables)
    assert set(BACKED_UP_TABLES) | set(EXCLUDED_TABLES) == model_tables
    assert not set(BACKED_UP_TABLES) & set(EXCLUDED_TABLES)
    assert all(reason.strip() for reason in EXCLUDED_TABLES.values())
    assert len(set(BACKED_UP_TABLES)) == len(BACKED_UP_TABLES)


def test_backup_tables_are_ordered_parents_first() -> None:
    seen: set[str] = set()
    for table in backup_tables():
        for foreign_key in table.foreign_keys:
            assert foreign_key.column.table.name in seen
        seen.add(table.name)
    assert seen == set(BACKED_UP_TABLES)


def test_sequence_reset_covers_every_serial_key_and_nothing_else() -> None:
    statements = sequence_reset_statements(Base.metadata.sorted_tables)
    targeted = {statement.split("FROM ")[1] for statement in statements}

    # user_profile's id is a foreign key to users, not a sequence of its own.
    assert "user_profile" not in targeted
    assert targeted == set(Base.metadata.tables) - {"user_profile"}
    users = next(s for s in statements if s.endswith("FROM users"))
    assert users == (
        "SELECT setval(pg_get_serial_sequence('users', 'id'), "
        "COALESCE(MAX(id), 0) + 1, false) FROM users"
    )


class _FakeSession:
    def __init__(self, dialect: str) -> None:
        self.dialect = dialect
        self.executed: list[str] = []

    def get_bind(self) -> Any:
        return SimpleNamespace(dialect=SimpleNamespace(name=self.dialect))

    async def execute(self, statement: Any) -> None:
        self.executed.append(str(statement))


async def test_sequences_are_reset_on_postgres_only() -> None:
    postgres = _FakeSession("postgresql")
    await reset_sequences(cast("AsyncSession", postgres))
    assert postgres.executed == sequence_reset_statements(Base.metadata.sorted_tables)

    sqlite = _FakeSession("sqlite")
    await reset_sequences(cast("AsyncSession", sqlite))
    assert sqlite.executed == []
