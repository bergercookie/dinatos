"""rename workouts to routines

Revision ID: e67c3fb73fdb
Revises: a4e7f1c92b3d
Create Date: 2026-10-01 00:00:00.000000

"""

from collections.abc import Sequence

from alembic import op

revision: str = "e67c3fb73fdb"
down_revision: str | Sequence[str] | None = "a4e7f1c92b3d"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.rename_table("workouts", "routines")
    op.execute("ALTER TABLE routines RENAME CONSTRAINT pk_workouts TO pk_routines")
    op.execute(
        "ALTER TABLE routines RENAME CONSTRAINT fk_workouts_owner_id_users "
        "TO fk_routines_owner_id_users"
    )
    op.execute("ALTER INDEX ix_workouts_owner_id RENAME TO ix_routines_owner_id")

    op.rename_table("workout_exercises", "routine_exercises")
    op.alter_column("routine_exercises", "workout_id", new_column_name="routine_id")
    op.execute(
        "ALTER TABLE routine_exercises RENAME CONSTRAINT pk_workout_exercises "
        "TO pk_routine_exercises"
    )
    op.execute(
        "ALTER TABLE routine_exercises "
        "RENAME CONSTRAINT fk_workout_exercises_exercise_id_exercises "
        "TO fk_routine_exercises_exercise_id_exercises"
    )
    op.execute(
        "ALTER TABLE routine_exercises RENAME CONSTRAINT fk_workout_exercises_workout_id_workouts "
        "TO fk_routine_exercises_routine_id_routines"
    )

    op.rename_table("workout_sets", "routine_sets")
    op.alter_column("routine_sets", "workout_exercise_id", new_column_name="routine_exercise_id")
    op.execute("ALTER TABLE routine_sets RENAME CONSTRAINT pk_workout_sets TO pk_routine_sets")
    op.execute(
        "ALTER TABLE routine_sets "
        "RENAME CONSTRAINT fk_workout_sets_workout_exercise_id_workout_exercises "
        "TO fk_routine_sets_routine_exercise_id_routine_exercises"
    )

    op.alter_column("activities", "workout_id", new_column_name="routine_id")
    op.execute(
        "ALTER TABLE activities RENAME CONSTRAINT fk_activities_workout_id_workouts "
        "TO fk_activities_routine_id_routines"
    )


def downgrade() -> None:
    op.execute(
        "ALTER TABLE activities RENAME CONSTRAINT fk_activities_routine_id_routines "
        "TO fk_activities_workout_id_workouts"
    )
    op.alter_column("activities", "routine_id", new_column_name="workout_id")

    op.execute(
        "ALTER TABLE routine_sets "
        "RENAME CONSTRAINT fk_routine_sets_routine_exercise_id_routine_exercises "
        "TO fk_workout_sets_workout_exercise_id_workout_exercises"
    )
    op.execute("ALTER TABLE routine_sets RENAME CONSTRAINT pk_routine_sets TO pk_workout_sets")
    op.alter_column("routine_sets", "routine_exercise_id", new_column_name="workout_exercise_id")
    op.rename_table("routine_sets", "workout_sets")

    op.execute(
        "ALTER TABLE routine_exercises RENAME CONSTRAINT fk_routine_exercises_routine_id_routines "
        "TO fk_workout_exercises_workout_id_workouts"
    )
    op.execute(
        "ALTER TABLE routine_exercises "
        "RENAME CONSTRAINT fk_routine_exercises_exercise_id_exercises "
        "TO fk_workout_exercises_exercise_id_exercises"
    )
    op.execute(
        "ALTER TABLE routine_exercises RENAME CONSTRAINT pk_routine_exercises "
        "TO pk_workout_exercises"
    )
    op.alter_column("routine_exercises", "routine_id", new_column_name="workout_id")
    op.rename_table("routine_exercises", "workout_exercises")

    op.execute("ALTER INDEX ix_routines_owner_id RENAME TO ix_workouts_owner_id")
    op.execute(
        "ALTER TABLE routines RENAME CONSTRAINT fk_routines_owner_id_users "
        "TO fk_workouts_owner_id_users"
    )
    op.execute("ALTER TABLE routines RENAME CONSTRAINT pk_routines TO pk_workouts")
    op.rename_table("routines", "workouts")
