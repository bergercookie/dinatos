from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator


class ApiKeyCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)

    @field_validator("name")
    @classmethod
    def _not_blank(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("name must not be blank")
        return value


class ApiKeyRead(BaseModel):
    """What listing shows: never the key, just enough to recognise it."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    suffix: str
    created_at: datetime
    last_used_at: datetime | None


class ApiKeyCreated(ApiKeyRead):
    """The response to creating a key -- the only time `key` is ever sent."""

    key: str
