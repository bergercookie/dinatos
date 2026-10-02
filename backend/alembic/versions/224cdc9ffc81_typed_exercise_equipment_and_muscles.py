"""typed exercise equipment and muscles

Revision ID: 224cdc9ffc81
Revises: 471e1447da05
Create Date: 2026-10-02 00:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "224cdc9ffc81"
down_revision: str | Sequence[str] | None = "471e1447da05"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_EQUIPMENT_VALUES = (
    "bands",
    "barbell",
    "body_only",
    "cable",
    "dumbbell",
    "e_z_curl_bar",
    "exercise_ball",
    "foam_roll",
    "kettlebells",
    "machine",
    "medicine_ball",
    "other",
)

_MUSCLE_GROUP_VALUES = (
    "abdominals",
    "abductors",
    "adductors",
    "biceps",
    "calves",
    "chest",
    "forearms",
    "glutes",
    "hamstrings",
    "lats",
    "lower_back",
    "middle_back",
    "neck",
    "quadriceps",
    "shoulders",
    "traps",
    "triceps",
)


def upgrade() -> None:
    # `471e1447da05` added these as free-text JSON lists; superseded here by
    # a closed `MuscleGroup` enum (see that model's docstring) -- a typo or
    # a provider's inconsistent spelling should never silently create a new,
    # never-matched "muscle" that can't be reasoned about alongside the rest.
    op.drop_column("exercises", "secondary_muscles")
    op.drop_column("exercises", "primary_muscles")

    bind = op.get_bind()
    equipment_enum = sa.Enum(*_EQUIPMENT_VALUES, name="equipment")
    musclegroup_enum = sa.Enum(*_MUSCLE_GROUP_VALUES, name="musclegroup")
    # Unlike a brand new table (see every other migration's `create_table`,
    # which creates its enum types as a side effect automatically), `ADD
    # COLUMN` on an existing table does not -- that event only fires for
    # `CREATE TABLE`, so the type has to be created explicitly first.
    equipment_enum.create(bind, checkfirst=False)

    op.add_column("exercises", sa.Column("equipment", equipment_enum, nullable=True))
    op.create_table(
        "exercise_muscles",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("exercise_id", sa.Integer(), nullable=False),
        sa.Column("muscle", musclegroup_enum, nullable=False),
        sa.Column("is_primary", sa.Boolean(), nullable=False),
        sa.ForeignKeyConstraint(["exercise_id"], ["exercises.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("exercise_id", "muscle"),
    )

    # Backfill the shipped catalog's own equipment/muscles from the same
    # vendored dataset `services.exercise.bootstrap_default_exercises` seeds
    # from -- same reasoning as `471e1447da05`'s own backfill: an instance
    # that was already running before this migration gets this metadata
    # applied to its existing rows, not just to rows created from here on.
    # A person's own custom exercise (no match by name) is left alone.
    from dinatos_backend.services.exercise import _equipment
    from dinatos_backend.services.exercise import exercise_muscles as _exercise_muscles
    from dinatos_backend.services.tutorials.free_exercise_db import load_free_exercise_db

    exercises = sa.table(
        "exercises",
        sa.column("id", sa.Integer),
        sa.column("name", sa.String),
        sa.column("equipment", equipment_enum),
    )
    exercise_muscles_table = sa.table(
        "exercise_muscles",
        sa.column("exercise_id", sa.Integer),
        sa.column("muscle", musclegroup_enum),
        sa.column("is_primary", sa.Boolean),
    )

    ids_by_name = {
        name: exercise_id
        for exercise_id, name in bind.execute(sa.select(exercises.c.id, exercises.c.name))
    }
    muscle_rows = []
    for entry in load_free_exercise_db():
        exercise_id = ids_by_name.get(entry["name"])
        if exercise_id is None:
            continue
        equipment = _equipment(entry.get("equipment"))
        if equipment is not None:
            bind.execute(
                exercises.update()
                .where(exercises.c.id == exercise_id)
                .values(equipment=equipment.value)
            )
        muscle_rows.extend(
            {
                "exercise_id": exercise_id,
                "muscle": exercise_muscle.muscle.value,
                "is_primary": exercise_muscle.is_primary,
            }
            for exercise_muscle in _exercise_muscles(
                entry["primaryMuscles"], entry["secondaryMuscles"]
            )
        )
    if muscle_rows:
        bind.execute(exercise_muscles_table.insert(), muscle_rows)


def downgrade() -> None:
    op.drop_table("exercise_muscles")
    # Postgres enums are independent objects that CREATE TABLE/ADD COLUMN
    # creates on demand but DROP TABLE/DROP COLUMN does not remove -- see
    # the initial migration's downgrade() for why this has to go explicitly
    # or the next upgrade's CREATE TYPE fails with "already exists".
    sa.Enum(name="musclegroup").drop(op.get_bind(), checkfirst=True)
    op.drop_column("exercises", "equipment")
    sa.Enum(name="equipment").drop(op.get_bind(), checkfirst=True)

    op.add_column(
        "exercises",
        sa.Column("primary_muscles", sa.JSON(), server_default=sa.text("'[]'"), nullable=False),
    )
    op.add_column(
        "exercises",
        sa.Column("secondary_muscles", sa.JSON(), server_default=sa.text("'[]'"), nullable=False),
    )
