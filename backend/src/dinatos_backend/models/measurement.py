from datetime import datetime

from sqlalchemy import DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column

from dinatos_backend.models.base import Base, TimestampMixin


class BodyMeasurement(Base, TimestampMixin):
    """A single dated set of body measurements. Every field but the date is
    optional, matching how people actually log these: whatever was measured
    that day, nothing more.

    Three loose groups share the one row (flat columns rather than separate
    tables: a single weigh-in or tape session is a single dated entry, and
    the backup is generic over columns): the basics and what a smart scale
    reports as a whole (weight, fat %, muscle/bone mass, water, BMI, ...), the
    scale's segmental analysis (fat % and muscle mass of each arm, leg and the
    trunk), and tape-measure circumferences.
    """

    __tablename__ = "body_measurements"

    id: Mapped[int] = mapped_column(primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    measured_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    weight_kg: Mapped[float | None]
    fat_percent: Mapped[float | None]
    muscle_mass_kg: Mapped[float | None]
    bone_mass_kg: Mapped[float | None]
    bmi: Mapped[float | None]
    dci_kcal: Mapped[int | None]
    metabolic_age: Mapped[int | None]
    water_percent: Mapped[float | None]
    visceral_fat: Mapped[float | None]
    # Segmental analysis, as a smart scale reports it.
    right_arm_fat_percent: Mapped[float | None]
    right_arm_muscle_kg: Mapped[float | None]
    left_arm_fat_percent: Mapped[float | None]
    left_arm_muscle_kg: Mapped[float | None]
    right_leg_fat_percent: Mapped[float | None]
    right_leg_muscle_kg: Mapped[float | None]
    left_leg_fat_percent: Mapped[float | None]
    left_leg_muscle_kg: Mapped[float | None]
    trunk_fat_percent: Mapped[float | None]
    trunk_muscle_kg: Mapped[float | None]
    # Tape measurements.
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
