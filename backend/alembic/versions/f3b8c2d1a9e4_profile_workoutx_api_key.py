"""profile workoutx api key

Revision ID: f3b8c2d1a9e4
Revises: 224cdc9ffc81
Create Date: 2026-10-03 00:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "f3b8c2d1a9e4"
down_revision: str | Sequence[str] | None = "224cdc9ffc81"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "user_profile", sa.Column("workoutx_api_key", sa.String(length=255), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("user_profile", "workoutx_api_key")
