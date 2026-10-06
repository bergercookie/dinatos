from datetime import datetime

from pydantic import BaseModel, ConfigDict

from dinatos_backend.models.routine import SetType


class ActivitySetBase(BaseModel):
    set_type: SetType = SetType.normal
    weight_kg: float | None = None
    reps: int | None = None
    distance_km: float | None = None
    duration_seconds: int | None = None


class ActivitySetCreate(ActivitySetBase):
    pass


class ActivitySetRead(ActivitySetBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    position: int


class ActivityExerciseBase(BaseModel):
    exercise_id: int
    superset_group: int | None = None
    notes: str | None = None


class ActivityExerciseCreate(ActivityExerciseBase):
    sets: list[ActivitySetCreate] = []


class ActivityExerciseRead(ActivityExerciseBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    position: int
    sets: list[ActivitySetRead]


class ActivityBase(BaseModel):
    title: str
    description: str | None = None
    started_at: datetime
    ended_at: datetime | None = None
    routine_id: int | None = None


class ActivityCreate(ActivityBase):
    """Also used to replace an activity in full via `PUT`."""

    exercises: list[ActivityExerciseCreate] = []


class ActivityRead(ActivityBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    exercises: list[ActivityExerciseRead]
