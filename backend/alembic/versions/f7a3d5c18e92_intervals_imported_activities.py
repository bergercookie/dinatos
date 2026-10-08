"""intervals.icu imported activities

Revision ID: f7a3d5c18e92
Revises: e8a2c5d94b13
Create Date: 2026-10-07 00:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "f7a3d5c18e92"
down_revision: str | Sequence[str] | None = "e8a2c5d94b13"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "intervals_imported_activities",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("owner_id", sa.Integer(), nullable=False),
        sa.Column("intervals_id", sa.String(length=64), nullable=False),
        sa.Column("activity_id", sa.Integer(), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
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
            ["activity_id"],
            ["activities.id"],
            name=op.f("fk_intervals_imported_activities_activity_id_activities"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["owner_id"],
            ["users.id"],
            name=op.f("fk_intervals_imported_activities_owner_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_intervals_imported_activities")),
        sa.UniqueConstraint(
            "owner_id", "intervals_id", name="uq_intervals_imported_owner_activity"
        ),
    )
    op.create_index(
        op.f("ix_intervals_imported_activities_owner_id"),
        "intervals_imported_activities",
        ["owner_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_intervals_imported_activities_activity_id"),
        "intervals_imported_activities",
        ["activity_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_intervals_imported_activities_activity_id"),
        table_name="intervals_imported_activities",
    )
    op.drop_index(
        op.f("ix_intervals_imported_activities_owner_id"),
        table_name="intervals_imported_activities",
    )
    op.drop_table("intervals_imported_activities")
