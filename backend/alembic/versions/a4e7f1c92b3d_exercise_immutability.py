"""exercise immutability

Revision ID: a4e7f1c92b3d
Revises: cd37b6cafd36
Create Date: 2026-09-29 00:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "a4e7f1c92b3d"
down_revision: str | Sequence[str] | None = "cd37b6cafd36"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "exercises",
        sa.Column("is_custom", sa.Boolean(), server_default=sa.true(), nullable=False),
    )

    # Existing rows that match the vendored seed dataset are the shipped
    # catalog, not something a person added -- backfill them to
    # is_custom=False so the immutability this column enables (see
    # `api.routers.exercises._ensure_custom`) also applies to an instance
    # that was already running before this migration, not just to rows
    # created afterwards.
    from dinatos_backend.services.tutorials.free_exercise_db import load_free_exercise_db

    seed_names = [entry["name"] for entry in load_free_exercise_db()]
    exercises = sa.table(
        "exercises", sa.column("name", sa.String), sa.column("is_custom", sa.Boolean)
    )
    op.execute(exercises.update().where(exercises.c.name.in_(seed_names)).values(is_custom=False))

    # Drop the server default now that every existing row has an explicit
    # value -- new rows get one from the ORM (`Exercise.is_custom`'s
    # `default=True`), same as every other boolean column on this table.
    op.alter_column("exercises", "is_custom", server_default=None)


def downgrade() -> None:
    op.drop_column("exercises", "is_custom")
