"""add tendinopathy / lower-leg rehab exercises to the catalog

Revision ID: b1d7e3f9a2c4
Revises: a9c4e7b2d6f1
Create Date: 2026-11-06 00:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.engine import Connection

revision: str = "b1d7e3f9a2c4"
down_revision: str | Sequence[str] | None = "a9c4e7b2d6f1"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def add_exercises(bind: Connection) -> None:
    """Adds `services.exercise_additions.ADDITIONS` to an existing catalog,
    reconciling with exercises a person may already have created by that
    exact name:

    - no such name: inserted as a built-in (`is_custom` false);
    - same name *and* the same weight/reps/distance/duration tracking: the
      person's own row is adopted -- flagged built-in, and given the
      equipment/muscles if it had none. Its id never changes, so every
      logged set, routine and planned workout already pointing at it stays
      attached; this is equivalent to creating a new row and moving the data
      across, without the moving;
    - same name but different tracking: it is a different exercise that just
      shares a name (names are unique), so the person's is left untouched and
      the addition skipped;
    - already a built-in: left alone.

    On an empty catalog this does nothing: startup seeding will create these
    along with the rest. (A person who deletes one of these afterwards
    won't see it return, as this runs once.)
    """
    from dinatos_backend.models.exercise import Equipment, MuscleGroup
    from dinatos_backend.services.exercise_additions import ADDITIONS

    equipment_enum = sa.Enum(*(e.value for e in Equipment), name="equipment", create_type=False)
    musclegroup_enum = sa.Enum(
        *(m.value for m in MuscleGroup), name="musclegroup", create_type=False
    )
    exercises = sa.table(
        "exercises",
        sa.column("id", sa.Integer),
        sa.column("name", sa.String),
        sa.column("tracks_weight", sa.Boolean),
        sa.column("tracks_reps", sa.Boolean),
        sa.column("tracks_distance", sa.Boolean),
        sa.column("tracks_duration", sa.Boolean),
        sa.column("is_custom", sa.Boolean),
        sa.column("equipment", equipment_enum),
    )
    muscles = sa.table(
        "exercise_muscles",
        sa.column("exercise_id", sa.Integer),
        sa.column("muscle", musclegroup_enum),
        sa.column("is_primary", sa.Boolean),
    )

    rows = bind.execute(sa.select(exercises)).all()
    if not rows:
        return
    existing = {row.name: row for row in rows}
    with_muscles = set(bind.execute(sa.select(muscles.c.exercise_id).distinct()).scalars())

    for add in ADDITIONS:
        current = existing.get(add.name)
        if current is None:
            exercise_id = bind.execute(
                exercises.insert()
                .values(
                    name=add.name,
                    tracks_weight=add.tracks_weight,
                    tracks_reps=add.tracks_reps,
                    tracks_distance=add.tracks_distance,
                    tracks_duration=add.tracks_duration,
                    is_custom=False,
                    equipment=add.equipment.value,
                )
                .returning(exercises.c.id)
            ).scalar_one()
            needs_muscles = True
        elif (
            current.is_custom
            and (
                current.tracks_weight,
                current.tracks_reps,
                current.tracks_distance,
                current.tracks_duration,
            )
            == add.specs
        ):
            exercise_id = current.id
            values: dict[str, object] = {"is_custom": False}
            if current.equipment is None:
                values["equipment"] = add.equipment.value
            bind.execute(exercises.update().where(exercises.c.id == exercise_id).values(**values))
            needs_muscles = exercise_id not in with_muscles
        else:
            continue
        if needs_muscles:
            bind.execute(
                muscles.insert(),
                [
                    {"exercise_id": exercise_id, "muscle": m.value, "is_primary": True}
                    for m in add.primary
                ]
                + [
                    {"exercise_id": exercise_id, "muscle": m.value, "is_primary": False}
                    for m in add.secondary
                ],
            )


def upgrade() -> None:
    add_exercises(op.get_bind())


def downgrade() -> None:
    # Deliberately a no-op: by now these rows may be referenced by a person's
    # logged activities or routines (a custom exercise may also have been
    # adopted), so deleting them would destroy data.
    pass
