from pydantic import BaseModel, ConfigDict

from dinatos_backend.models.profile import UnitSystem


class ProfileUpdate(BaseModel):
    height_cm: float | None = None
    unit_system: UnitSystem | None = None


class ProfileRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    height_cm: float | None
    unit_system: UnitSystem
