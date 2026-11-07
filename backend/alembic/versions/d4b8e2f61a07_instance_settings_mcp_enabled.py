"""instance settings: mcp_enabled

Revision ID: d4b8e2f61a07
Revises: c2f5a8d91b36
Create Date: 2026-11-08 00:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "d4b8e2f61a07"
down_revision: str | Sequence[str] | None = "c2f5a8d91b36"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("instance_settings", sa.Column("mcp_enabled", sa.Boolean(), nullable=True))


def downgrade() -> None:
    op.drop_column("instance_settings", "mcp_enabled")
