from sqlalchemy import Boolean
from sqlalchemy.orm import Mapped, mapped_column

from dinatos_backend.models.base import Base, TimestampMixin


class InstanceSettings(Base, TimestampMixin):
    """Server-wide options an admin changes from the app, as one row (`id` is
    always 1; the row is created the first time something is saved).

    A column is `NULL` until an admin chooses a value, so "never chosen" and
    "chosen" stay distinguishable: the code default applies to the former.
    Anything the operator pins with an environment variable wins over the
    stored value (see `services.instance_settings`).
    """

    __tablename__ = "instance_settings"

    id: Mapped[int] = mapped_column(primary_key=True)
    allow_registration: Mapped[bool | None] = mapped_column(Boolean)
    mcp_enabled: Mapped[bool | None] = mapped_column(Boolean)
