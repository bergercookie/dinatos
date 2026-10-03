"""routine exercise superset group

Revision ID: a7c1d9e04b52
Revises: f3b8c2d1a9e4
Create Date: 2026-10-03 12:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "a7c1d9e04b52"
down_revision: str | Sequence[str] | None = "f3b8c2d1a9e4"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("routine_exercises", sa.Column("superset_group", sa.Integer(), nullable=True))


def downgrade() -> None:
    op.drop_column("routine_exercises", "superset_group")
