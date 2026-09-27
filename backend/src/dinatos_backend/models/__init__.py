"""SQLAlchemy models. Import every module here so `Base.metadata` sees all
tables -- Alembic's autogenerate and `Base.metadata.create_all` in tests both
rely on that.
"""

from dinatos_backend.models.activity import Activity, ActivityExercise, ActivitySet
from dinatos_backend.models.auth_session import AuthSession
from dinatos_backend.models.base import Base, TimestampMixin
from dinatos_backend.models.exercise import Exercise
from dinatos_backend.models.hevy_import import HevyImportKind, HevyImportRecord
from dinatos_backend.models.measurement import BodyMeasurement
from dinatos_backend.models.profile import UnitSystem, UserProfile
from dinatos_backend.models.user import User
from dinatos_backend.models.workout import SetType, Workout, WorkoutExercise, WorkoutSet

__all__ = [
    "Activity",
    "ActivityExercise",
    "ActivitySet",
    "AuthSession",
    "Base",
    "BodyMeasurement",
    "Exercise",
    "HevyImportKind",
    "HevyImportRecord",
    "SetType",
    "TimestampMixin",
    "UnitSystem",
    "User",
    "UserProfile",
    "Workout",
    "WorkoutExercise",
    "WorkoutSet",
]
