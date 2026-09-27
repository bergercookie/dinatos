from pydantic import BaseModel, ConfigDict

from dinatos_backend.models.workout import SetType


class WorkoutSetBase(BaseModel):
    set_type: SetType = SetType.normal
    target_weight_kg: float | None = None
    target_reps: int | None = None
    target_distance_km: float | None = None
    target_duration_seconds: int | None = None


class WorkoutSetCreate(WorkoutSetBase):
    pass


class WorkoutSetRead(WorkoutSetBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    position: int


class WorkoutExerciseBase(BaseModel):
    exercise_id: int
    notes: str | None = None


class WorkoutExerciseCreate(WorkoutExerciseBase):
    sets: list[WorkoutSetCreate] = []


class WorkoutExerciseRead(WorkoutExerciseBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    position: int
    sets: list[WorkoutSetRead]


class WorkoutBase(BaseModel):
    name: str
    description: str | None = None


class WorkoutCreate(WorkoutBase):
    """Also used to replace a workout in full via `PUT` -- there is no
    separate partial-update schema for the nested exercises/sets structure.
    """

    exercises: list[WorkoutExerciseCreate] = []


class WorkoutRead(WorkoutBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    exercises: list[WorkoutExerciseRead]
