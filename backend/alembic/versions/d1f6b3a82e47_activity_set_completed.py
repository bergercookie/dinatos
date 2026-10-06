"""per-set completed flag

Revision ID: d1f6b3a82e47
Revises: c9e4a7b15d28
Create Date: 2026-10-06 00:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "d1f6b3a82e47"
down_revision: str | Sequence[str] | None = "c9e4a7b15d28"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Every set logged so far was one the person did: completed.
    op.add_column(
        "activity_sets",
        sa.Column("completed", sa.Boolean(), server_default=sa.true(), nullable=False),
    )


def downgrade() -> None:
    op.drop_column("activity_sets", "completed")
