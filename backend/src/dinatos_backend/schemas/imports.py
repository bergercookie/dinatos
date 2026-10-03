from pydantic import BaseModel

from dinatos_backend.models.exercise import Equipment, MuscleGroup


class ImportedExercise(BaseModel):
    """A custom exercise this import had to create because no catalog
    exercise matched it exactly, with whatever equipment/muscles were
    *guessed* for it (see `services.hevy_exercise_infer`). The guesses are
    already saved on the exercise; the flags say which of its fields came
    from a guess rather than from the person, so the UI can ask for a review.
    """

    id: int
    name: str
    equipment: Equipment | None = None
    primary_muscles: list[MuscleGroup] = []
    secondary_muscles: list[MuscleGroup] = []
    equipment_guessed: bool = False
    muscles_guessed: bool = False


class HevyWorkoutImportResult(BaseModel):
    activities_created: int
    exercises_created: int
    # One entry per exercise counted in `exercises_created`, in file order.
    created_exercises: list[ImportedExercise] = []


class HevyMeasurementImportResult(BaseModel):
    measurements_created: int
