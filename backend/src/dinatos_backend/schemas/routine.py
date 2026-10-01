from pydantic import BaseModel, ConfigDict

from dinatos_backend.models.routine import SetType


class RoutineSetBase(BaseModel):
    set_type: SetType = SetType.normal
    target_weight_kg: float | None = None
    target_reps: int | None = None
    target_distance_km: float | None = None
    target_duration_seconds: int | None = None


class RoutineSetCreate(RoutineSetBase):
    pass


class RoutineSetRead(RoutineSetBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    position: int


class RoutineExerciseBase(BaseModel):
    exercise_id: int
    notes: str | None = None


class RoutineExerciseCreate(RoutineExerciseBase):
    sets: list[RoutineSetCreate] = []


class RoutineExerciseRead(RoutineExerciseBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    position: int
    sets: list[RoutineSetRead]


class RoutineBase(BaseModel):
    name: str
    description: str | None = None


class RoutineCreate(RoutineBase):
    """Also used to replace a routine in full via `PUT` -- there is no
    separate partial-update schema for the nested exercises/sets structure.
    """

    exercises: list[RoutineExerciseCreate] = []


class RoutineRead(RoutineBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    exercises: list[RoutineExerciseRead]
