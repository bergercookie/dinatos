"""Documents for the two export/import features: the admin's full server
backup (`GET /admin/backup`, `POST /admin/backup/restore`) and a user's own
data export (`GET /profile/export`, `POST /profile/import`).

Both are a versioned JSON envelope -- a `format` name, a `format_version`
and who/when produced it -- so a file is recognisable, and an incompatible
one is rejected up front with a clear message instead of half-applied. See
`docs/architecture/backend.md`'s "Backup and data export".
"""

import enum
from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field

from dinatos_backend.models.exercise import Equipment, MuscleGroup
from dinatos_backend.models.profile import UnitSystem
from dinatos_backend.models.routine import SetType

BACKUP_FORMAT = "dinatos-backup"
USER_EXPORT_FORMAT = "dinatos-user-export"
# Bumped only for a change an older reader cannot interpret (a table or
# column removed or re-meant). Adding a nullable column or a defaulted one is
# not such a change -- see `services.backup.parse_backup`.
FORMAT_VERSION = 1


class FullBackup(BaseModel):
    """The whole server: every table in `services.backup.BACKED_UP_TABLES`,
    as lists of `{column: value}` rows carrying their original primary keys.
    """

    format: str = BACKUP_FORMAT
    format_version: int = FORMAT_VERSION
    exported_at: datetime
    app_version: str
    tables: dict[str, list[dict[str, Any]]]


class BackupRestoreResult(BaseModel):
    rows: dict[str, int]
    # Whether the calling admin's own login survived the restore -- see
    # `services.backup.restore_backup`.
    session_kept: bool


class _ExportedSet(BaseModel):
    set_type: SetType = SetType.normal


class ExportedRoutineSet(_ExportedSet):
    target_weight_kg: float | None = None
    target_reps: int | None = None
    target_distance_km: float | None = None
    target_duration_seconds: int | None = None


class ExportedActivitySet(_ExportedSet):
    weight_kg: float | None = None
    reps: int | None = None
    distance_km: float | None = None
    duration_seconds: int | None = None


class ExportedExercise(BaseModel):
    """A catalog entry a routine or activity refers to, by `name`."""

    name: str = Field(min_length=1, max_length=200)
    tracks_weight: bool = True
    tracks_reps: bool = True
    tracks_distance: bool = False
    tracks_duration: bool = False
    equipment: Equipment | None = None
    primary_muscles: list[MuscleGroup] = []
    secondary_muscles: list[MuscleGroup] = []


class ExportedRoutineExercise(BaseModel):
    exercise: str = Field(min_length=1, max_length=200)
    superset_group: int | None = None
    notes: str | None = Field(default=None, max_length=2000)
    sets: list[ExportedRoutineSet] = []


class ExportedRoutine(BaseModel):
    # Export-local identifier (1-based position in the file), only there so
    # an activity can say which routine it was run from -- never a database id.
    ref: int
    name: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=2000)
    exercises: list[ExportedRoutineExercise] = []


class ExportedActivityExercise(BaseModel):
    exercise: str = Field(min_length=1, max_length=200)
    superset_group: int | None = None
    notes: str | None = Field(default=None, max_length=2000)
    sets: list[ExportedActivitySet] = []


class ExportedActivity(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=2000)
    started_at: datetime
    ended_at: datetime | None = None
    routine_ref: int | None = None
    exercises: list[ExportedActivityExercise] = []


class ExportedMeasurement(BaseModel):
    measured_at: datetime
    weight_kg: float | None = None
    fat_percent: float | None = None
    muscle_mass_kg: float | None = None
    bone_mass_kg: float | None = None
    bmi: float | None = None
    dci_kcal: int | None = None
    metabolic_age: int | None = None
    water_percent: float | None = None
    visceral_fat: float | None = None
    right_arm_fat_percent: float | None = None
    right_arm_muscle_kg: float | None = None
    left_arm_fat_percent: float | None = None
    left_arm_muscle_kg: float | None = None
    right_leg_fat_percent: float | None = None
    right_leg_muscle_kg: float | None = None
    left_leg_fat_percent: float | None = None
    left_leg_muscle_kg: float | None = None
    trunk_fat_percent: float | None = None
    trunk_muscle_kg: float | None = None
    neck_cm: float | None = None
    shoulder_cm: float | None = None
    chest_cm: float | None = None
    left_bicep_cm: float | None = None
    right_bicep_cm: float | None = None
    left_forearm_cm: float | None = None
    right_forearm_cm: float | None = None
    abdomen_cm: float | None = None
    waist_cm: float | None = None
    hips_cm: float | None = None
    left_thigh_cm: float | None = None
    right_thigh_cm: float | None = None
    left_calf_cm: float | None = None
    right_calf_cm: float | None = None


class ExportedProfile(BaseModel):
    """Display settings only -- never the WorkoutX API key, which is a
    credential and stays on the server it was entered on.
    """

    height_cm: float | None = None
    unit_system: UnitSystem = UnitSystem.metric


class UserExport(BaseModel):
    """One user's own data: no ids, no password hash, no API key."""

    format: Literal["dinatos-user-export"] = "dinatos-user-export"
    format_version: Literal[1] = 1
    exported_at: datetime
    app_version: str
    profile: ExportedProfile
    exercises: list[ExportedExercise] = []
    routines: list[ExportedRoutine] = []
    activities: list[ExportedActivity] = []
    measurements: list[ExportedMeasurement] = []


class UserImportMode(enum.Enum):
    merge = "merge"
    replace = "replace"


class UserImportCounts(BaseModel):
    exercises: int = 0
    routines: int = 0
    activities: int = 0
    measurements: int = 0


class ClearDataResult(BaseModel):
    """What `DELETE /profile/data` removed (`exercises` counts only custom
    exercises nobody else still uses)."""

    deleted: UserImportCounts


class UserImportResult(BaseModel):
    mode: UserImportMode
    created: UserImportCounts
    # Merge only: already present in the account, so left alone.
    skipped: UserImportCounts
    # Replace only: the caller's rows removed before importing.
    deleted: UserImportCounts
