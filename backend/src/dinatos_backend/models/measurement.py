from datetime import datetime

from sqlalchemy import DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column

from dinatos_backend.models.base import Base, TimestampMixin


class BodyMeasurement(Base, TimestampMixin):
    """A single dated set of body measurements. Every field but the date is
    optional, matching how people actually log these: whatever was measured
    that day, nothing more.
    """

    __tablename__ = "body_measurements"

    id: Mapped[int] = mapped_column(primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    measured_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    weight_kg: Mapped[float | None]
    fat_percent: Mapped[float | None]
    neck_cm: Mapped[float | None]
    shoulder_cm: Mapped[float | None]
    chest_cm: Mapped[float | None]
    left_bicep_cm: Mapped[float | None]
    right_bicep_cm: Mapped[float | None]
    left_forearm_cm: Mapped[float | None]
    right_forearm_cm: Mapped[float | None]
    abdomen_cm: Mapped[float | None]
    waist_cm: Mapped[float | None]
    hips_cm: Mapped[float | None]
    left_thigh_cm: Mapped[float | None]
    right_thigh_cm: Mapped[float | None]
    left_calf_cm: Mapped[float | None]
    right_calf_cm: Mapped[float | None]
