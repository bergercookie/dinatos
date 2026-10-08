"""planned workouts and calendar feed token

Revision ID: a9c4e7b2d6f1
Revises: f7a3d5c18e92
Create Date: 2026-10-08 00:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "a9c4e7b2d6f1"
down_revision: str | Sequence[str] | None = "f7a3d5c18e92"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "planned_workouts",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("owner_id", sa.Integer(), nullable=False),
        sa.Column("routine_id", sa.Integer(), nullable=True),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("notes", sa.String(length=2000), nullable=True),
        sa.Column("scheduled_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("duration_minutes", sa.Integer(), nullable=False),
        sa.Column("reminder_minutes", sa.Integer(), nullable=True),
        sa.Column("completed_activity_id", sa.Integer(), nullable=True),
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
        sa.ForeignKeyConstraint(
            ["completed_activity_id"],
            ["activities.id"],
            name=op.f("fk_planned_workouts_completed_activity_id_activities"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["owner_id"],
            ["users.id"],
            name=op.f("fk_planned_workouts_owner_id_users"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["routine_id"],
            ["routines.id"],
            name=op.f("fk_planned_workouts_routine_id_routines"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_planned_workouts")),
    )
    op.create_index(
        op.f("ix_planned_workouts_owner_id"), "planned_workouts", ["owner_id"], unique=False
    )
    op.create_index(
        op.f("ix_planned_workouts_scheduled_at"), "planned_workouts", ["scheduled_at"], unique=False
    )
    op.add_column("user_profile", sa.Column("calendar_token", sa.String(length=64), nullable=True))
    op.create_index(
        op.f("ix_user_profile_calendar_token"), "user_profile", ["calendar_token"], unique=True
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_user_profile_calendar_token"), table_name="user_profile")
    op.drop_column("user_profile", "calendar_token")
    op.drop_index(op.f("ix_planned_workouts_scheduled_at"), table_name="planned_workouts")
    op.drop_index(op.f("ix_planned_workouts_owner_id"), table_name="planned_workouts")
    op.drop_table("planned_workouts")
