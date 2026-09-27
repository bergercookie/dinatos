"""user accounts and multi-user ownership

Revision ID: db5505c9f4ca
Revises: 705379650c17
Create Date: 2026-09-27 10:23:42.848904

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "db5505c9f4ca"
down_revision: str | Sequence[str] | None = "705379650c17"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("email", sa.String(length=320), nullable=False),
        sa.Column("password_hash", sa.String(length=255), nullable=False),
        sa.Column("is_admin", sa.Boolean(), nullable=False),
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
        sa.PrimaryKeyConstraint("id", name=op.f("pk_users")),
    )
    op.create_index(op.f("ix_users_email"), "users", ["email"], unique=True)

    op.add_column("activities", sa.Column("owner_id", sa.Integer(), nullable=False))
    op.create_index(op.f("ix_activities_owner_id"), "activities", ["owner_id"], unique=False)
    op.create_foreign_key(
        op.f("fk_activities_owner_id_users"),
        "activities",
        "users",
        ["owner_id"],
        ["id"],
        ondelete="CASCADE",
    )

    op.add_column("body_measurements", sa.Column("owner_id", sa.Integer(), nullable=False))
    op.create_index(
        op.f("ix_body_measurements_owner_id"), "body_measurements", ["owner_id"], unique=False
    )
    op.create_foreign_key(
        op.f("fk_body_measurements_owner_id_users"),
        "body_measurements",
        "users",
        ["owner_id"],
        ["id"],
        ondelete="CASCADE",
    )

    op.add_column("hevy_import_records", sa.Column("owner_id", sa.Integer(), nullable=False))
    op.create_index(
        op.f("ix_hevy_import_records_owner_id"), "hevy_import_records", ["owner_id"], unique=False
    )
    op.create_foreign_key(
        op.f("fk_hevy_import_records_owner_id_users"),
        "hevy_import_records",
        "users",
        ["owner_id"],
        ["id"],
        ondelete="CASCADE",
    )

    # One profile row per user, keyed by that user's own id.
    op.create_foreign_key(
        op.f("fk_user_profile_id_users"),
        "user_profile",
        "users",
        ["id"],
        ["id"],
        ondelete="CASCADE",
    )

    op.add_column("workouts", sa.Column("owner_id", sa.Integer(), nullable=False))
    op.create_index(op.f("ix_workouts_owner_id"), "workouts", ["owner_id"], unique=False)
    op.create_foreign_key(
        op.f("fk_workouts_owner_id_users"),
        "workouts",
        "users",
        ["owner_id"],
        ["id"],
        ondelete="CASCADE",
    )


def downgrade() -> None:
    op.drop_constraint(op.f("fk_workouts_owner_id_users"), "workouts", type_="foreignkey")
    op.drop_index(op.f("ix_workouts_owner_id"), table_name="workouts")
    op.drop_column("workouts", "owner_id")

    op.drop_constraint(op.f("fk_user_profile_id_users"), "user_profile", type_="foreignkey")

    op.drop_constraint(
        op.f("fk_hevy_import_records_owner_id_users"), "hevy_import_records", type_="foreignkey"
    )
    op.drop_index(op.f("ix_hevy_import_records_owner_id"), table_name="hevy_import_records")
    op.drop_column("hevy_import_records", "owner_id")

    op.drop_constraint(
        op.f("fk_body_measurements_owner_id_users"), "body_measurements", type_="foreignkey"
    )
    op.drop_index(op.f("ix_body_measurements_owner_id"), table_name="body_measurements")
    op.drop_column("body_measurements", "owner_id")

    op.drop_constraint(op.f("fk_activities_owner_id_users"), "activities", type_="foreignkey")
    op.drop_index(op.f("ix_activities_owner_id"), table_name="activities")
    op.drop_column("activities", "owner_id")

    op.drop_index(op.f("ix_users_email"), table_name="users")
    op.drop_table("users")
