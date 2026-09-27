"""hevy import records

Revision ID: 705379650c17
Revises: cb19a35c97e8
Create Date: 2026-09-27 09:37:44.915915

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "705379650c17"
down_revision: str | Sequence[str] | None = "cb19a35c97e8"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "hevy_import_records",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column(
            "kind", sa.Enum("workouts", "measurements", name="hevyimportkind"), nullable=False
        ),
        sa.Column("content_hash", sa.String(length=64), nullable=False),
        sa.Column("filename", sa.String(length=255), nullable=True),
        sa.Column("activities_created", sa.Integer(), nullable=True),
        sa.Column("exercises_created", sa.Integer(), nullable=True),
        sa.Column("measurements_created", sa.Integer(), nullable=True),
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
        op.f("ix_hevy_import_records_content_hash"),
        "hevy_import_records",
        ["content_hash"],
        unique=False,
    )
    op.create_index(
        op.f("ix_hevy_import_records_kind"), "hevy_import_records", ["kind"], unique=False
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_hevy_import_records_kind"), table_name="hevy_import_records")
    op.drop_index(op.f("ix_hevy_import_records_content_hash"), table_name="hevy_import_records")
    op.drop_table("hevy_import_records")
    # See the initial migration's downgrade() for why this enum needs an
    # explicit drop: DROP TABLE alone leaves the Postgres type behind, and
    # the next upgrade's CREATE TYPE then fails with "already exists".
    sa.Enum(name="hevyimportkind").drop(op.get_bind(), checkfirst=True)
