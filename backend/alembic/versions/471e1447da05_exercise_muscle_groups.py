"""exercise muscle groups

Revision ID: 471e1447da05
Revises: e67c3fb73fdb
Create Date: 2026-10-02 00:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "471e1447da05"
down_revision: str | Sequence[str] | None = "e67c3fb73fdb"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "exercises",
        sa.Column("primary_muscles", sa.JSON(), server_default=sa.text("'[]'"), nullable=False),
    )
    op.add_column(
        "exercises",
        sa.Column("secondary_muscles", sa.JSON(), server_default=sa.text("'[]'"), nullable=False),
    )

    # Backfill the shipped catalog's own muscle lists -- same source
    # `services.exercise.bootstrap_default_exercises` seeds new instances
    # from, so an instance that was already running before this migration
    # gets the same values a fresh one would. A person's own custom
    # exercise is left at the server default (`[]`) -- there's no muscle
    # data to backfill it from, same reasoning as the `is_custom` backfill
    # in `a4e7f1c92b3d_exercise_immutability.py` only touching seeded rows.
    from dinatos_backend.services.tutorials.free_exercise_db import load_free_exercise_db

    exercises = sa.table(
        "exercises",
        sa.column("name", sa.String),
        sa.column("primary_muscles", sa.JSON),
        sa.column("secondary_muscles", sa.JSON),
    )
    connection = op.get_bind()
    for entry in load_free_exercise_db():
        connection.execute(
            exercises.update()
            .where(exercises.c.name == entry["name"])
            .values(
                primary_muscles=entry["primaryMuscles"],
                secondary_muscles=entry["secondaryMuscles"],
            )
        )

    # Drop the server defaults now that every existing row has an explicit
    # value -- new rows get one from the ORM (`Exercise.primary_muscles`/
    # `secondary_muscles`'s `default=list`), same as `is_custom` above.
    op.alter_column("exercises", "primary_muscles", server_default=None)
    op.alter_column("exercises", "secondary_muscles", server_default=None)


def downgrade() -> None:
    op.drop_column("exercises", "secondary_muscles")
    op.drop_column("exercises", "primary_muscles")
