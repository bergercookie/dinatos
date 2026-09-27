from datetime import datetime

from pydantic import BaseModel, ConfigDict


class BodyMeasurementBase(BaseModel):
    measured_at: datetime
    weight_kg: float | None = None
    fat_percent: float | None = None
    neck_cm: float | None = None
    shoulder_cm: float | None = None
    chest_cm: float | None = None
    left_bicep_cm: float | None = None
    right_bicep_cm: float | None = None
    left_forearm_cm: float | None = None
    right_forearm_cm: float | None = None
    abdomen_cm: float | None = None
    waist_cm: float | None = None
    hips_cm: float | None = None
    left_thigh_cm: float | None = None
    right_thigh_cm: float | None = None
    left_calf_cm: float | None = None
    right_calf_cm: float | None = None


class BodyMeasurementCreate(BodyMeasurementBase):
    pass


class BodyMeasurementRead(BodyMeasurementBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
