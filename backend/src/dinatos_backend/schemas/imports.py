from pydantic import BaseModel


class HevyWorkoutImportResult(BaseModel):
    activities_created: int
    exercises_created: int


class HevyMeasurementImportResult(BaseModel):
    measurements_created: int
