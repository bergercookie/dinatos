"""SQLAlchemy models. Import every module here so `Base.metadata` sees all
tables -- Alembic's autogenerate and `Base.metadata.create_all` in tests both
rely on that.
"""

from dinatos_backend.models.activity import Activity, ActivityExercise, ActivitySet
from dinatos_backend.models.api_key import ApiKey
from dinatos_backend.models.auth_session import AuthSession
from dinatos_backend.models.base import Base, TimestampMixin
from dinatos_backend.models.exercise import Equipment, Exercise, ExerciseMuscle, MuscleGroup
from dinatos_backend.models.hevy_import import HevyImportKind, HevyImportRecord
from dinatos_backend.models.intervals_import import IntervalsImportedActivity
from dinatos_backend.models.measurement import BodyMeasurement
from dinatos_backend.models.profile import UnitSystem, UserProfile
from dinatos_backend.models.routine import Routine, RoutineExercise, RoutineSet, SetType
from dinatos_backend.models.user import User

__all__ = [
    "Activity",
    "ActivityExercise",
    "ActivitySet",
    "ApiKey",
    "AuthSession",
    "Base",
    "BodyMeasurement",
    "Equipment",
    "Exercise",
    "ExerciseMuscle",
    "HevyImportKind",
    "HevyImportRecord",
    "IntervalsImportedActivity",
    "MuscleGroup",
    "Routine",
    "RoutineExercise",
    "RoutineSet",
    "SetType",
    "TimestampMixin",
    "UnitSystem",
    "User",
    "UserProfile",
]
