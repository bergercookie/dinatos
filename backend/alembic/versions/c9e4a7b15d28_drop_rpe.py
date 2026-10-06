"""drop the per-set RPE

Revision ID: c9e4a7b15d28
Revises: b8d2e6f40a17
Create Date: 2026-10-06 00:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "c9e4a7b15d28"
down_revision: str | Sequence[str] | None = "b8d2e6f40a17"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_column("activity_sets", "rpe")


def downgrade() -> None:
    op.add_column("activity_sets", sa.Column("rpe", sa.Double(), nullable=True))
