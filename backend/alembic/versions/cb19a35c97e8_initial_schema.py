"""initial schema

Revision ID: cb19a35c97e8
Revises:
Create Date: 2026-09-27 09:12:05.862150

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "cb19a35c97e8"
down_revision: str | Sequence[str] | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "body_measurements",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("measured_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("weight_kg", sa.Double(), nullable=True),
        sa.Column("fat_percent", sa.Double(), nullable=True),
        sa.Column("neck_cm", sa.Double(), nullable=True),
        sa.Column("shoulder_cm", sa.Double(), nullable=True),
        sa.Column("chest_cm", sa.Double(), nullable=True),
        sa.Column("left_bicep_cm", sa.Double(), nullable=True),
        sa.Column("right_bicep_cm", sa.Double(), nullable=True),
        sa.Column("left_forearm_cm", sa.Double(), nullable=True),
        sa.Column("right_forearm_cm", sa.Double(), nullable=True),
        sa.Column("abdomen_cm", sa.Double(), nullable=True),
        sa.Column("waist_cm", sa.Double(), nullable=True),
        sa.Column("hips_cm", sa.Double(), nullable=True),
        sa.Column("left_thigh_cm", sa.Double(), nullable=True),
        sa.Column("right_thigh_cm", sa.Double(), nullable=True),
        sa.Column("left_calf_cm", sa.Double(), nullable=True),
        sa.Column("right_calf_cm", sa.Double(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_body_measurements_measured_at"), "body_measurements", ["measured_at"], unique=False
    )
    op.create_table(
        "exercises",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("tracks_weight", sa.Boolean(), nullable=False),
        sa.Column("tracks_reps", sa.Boolean(), nullable=False),
        sa.Column("tracks_distance", sa.Boolean(), nullable=False),
        sa.Column("tracks_duration", sa.Boolean(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_exercises_name"), "exercises", ["name"], unique=True)
    op.create_table(
        "user_profile",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("height_cm", sa.Double(), nullable=True),
        sa.Column("unit_system", sa.Enum("metric", "imperial", name="unitsystem"), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "workouts",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("description", sa.String(length=2000), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "activities",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("workout_id", sa.Integer(), nullable=True),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("description", sa.String(length=2000), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["workout_id"], ["workouts.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "workout_exercises",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("workout_id", sa.Integer(), nullable=False),
        sa.Column("exercise_id", sa.Integer(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("notes", sa.String(length=2000), nullable=True),
        sa.ForeignKeyConstraint(["exercise_id"], ["exercises.id"]),
        sa.ForeignKeyConstraint(["workout_id"], ["workouts.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "activity_exercises",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("activity_id", sa.Integer(), nullable=False),
        sa.Column("exercise_id", sa.Integer(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("superset_group", sa.Integer(), nullable=True),
        sa.Column("notes", sa.String(length=2000), nullable=True),
        sa.ForeignKeyConstraint(["activity_id"], ["activities.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["exercise_id"], ["exercises.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "workout_sets",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("workout_exercise_id", sa.Integer(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column(
            "set_type",
            sa.Enum("normal", "warmup", "dropset", "failure", name="settype"),
            nullable=False,
        ),
        sa.Column("target_weight_kg", sa.Double(), nullable=True),
        sa.Column("target_reps", sa.Integer(), nullable=True),
        sa.Column("target_distance_km", sa.Double(), nullable=True),
        sa.Column("target_duration_seconds", sa.Integer(), nullable=True),
        sa.ForeignKeyConstraint(
            ["workout_exercise_id"], ["workout_exercises.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "activity_sets",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("activity_exercise_id", sa.Integer(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column(
            "set_type",
            sa.Enum("normal", "warmup", "dropset", "failure", name="settype"),
            nullable=False,
        ),
        sa.Column("weight_kg", sa.Double(), nullable=True),
        sa.Column("reps", sa.Integer(), nullable=True),
        sa.Column("distance_km", sa.Double(), nullable=True),
        sa.Column("duration_seconds", sa.Integer(), nullable=True),
        sa.Column("rpe", sa.Double(), nullable=True),
        sa.ForeignKeyConstraint(
            ["activity_exercise_id"], ["activity_exercises.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )


def downgrade() -> None:
    op.drop_table("activity_sets")
    op.drop_table("workout_sets")
    # Both tables above share the "settype" enum type; Postgres enums are
    # independent objects that CREATE TABLE creates on demand but DROP TABLE
    # does not remove, so it has to go explicitly or the next upgrade's
    # CREATE TYPE fails with "already exists".
    sa.Enum(name="settype").drop(op.get_bind(), checkfirst=True)
    op.drop_table("activity_exercises")
    op.drop_table("workout_exercises")
    op.drop_table("activities")
    op.drop_table("workouts")
    op.drop_table("user_profile")
    sa.Enum(name="unitsystem").drop(op.get_bind(), checkfirst=True)
    op.drop_index(op.f("ix_exercises_name"), table_name="exercises")
    op.drop_table("exercises")
    op.drop_index(op.f("ix_body_measurements_measured_at"), table_name="body_measurements")
    op.drop_table("body_measurements")
