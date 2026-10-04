"""body measurements: smart scale body composition and segmental analysis

Revision ID: b8d2e6f40a17
Revises: a7c1d9e04b52
Create Date: 2026-10-04 00:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "b8d2e6f40a17"
down_revision: str | Sequence[str] | None = "a7c1d9e04b52"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# All nullable: an entry only holds what was measured that day.
_NEW_COLUMNS = (
    ("muscle_mass_kg", sa.Float()),
    ("bone_mass_kg", sa.Float()),
    ("bmi", sa.Float()),
    ("dci_kcal", sa.Integer()),
    ("metabolic_age", sa.Integer()),
    ("water_percent", sa.Float()),
    ("visceral_fat", sa.Float()),
    ("right_arm_fat_percent", sa.Float()),
    ("right_arm_muscle_kg", sa.Float()),
    ("left_arm_fat_percent", sa.Float()),
    ("left_arm_muscle_kg", sa.Float()),
    ("right_leg_fat_percent", sa.Float()),
    ("right_leg_muscle_kg", sa.Float()),
    ("left_leg_fat_percent", sa.Float()),
    ("left_leg_muscle_kg", sa.Float()),
    ("trunk_fat_percent", sa.Float()),
    ("trunk_muscle_kg", sa.Float()),
)


def upgrade() -> None:
    for name, type_ in _NEW_COLUMNS:
        op.add_column("body_measurements", sa.Column(name, type_, nullable=True))


def downgrade() -> None:
    for name, _ in reversed(_NEW_COLUMNS):
        op.drop_column("body_measurements", name)
