from pydantic import BaseModel, ConfigDict, Field, computed_field, field_validator

from dinatos_backend.models.profile import UnitSystem


class ProfileUpdate(BaseModel):
    height_cm: float | None = None
    unit_system: UnitSystem | None = None
    # Write-only: a blank or null value clears the key.
    workoutx_api_key: str | None = Field(default=None, max_length=255)

    @field_validator("workoutx_api_key")
    @classmethod
    def _blank_key_clears(cls, value: str | None) -> str | None:
        value = value.strip() if value else None
        return value or None


class ProfileRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    height_cm: float | None
    unit_system: UnitSystem

    # Never echo the key itself back -- the UI only needs to know whether
    # one is saved.
    workoutx_api_key: str | None = Field(default=None, exclude=True)

    @computed_field  # type: ignore[prop-decorator]
    @property
    def has_workoutx_api_key(self) -> bool:
        return bool(self.workoutx_api_key)
