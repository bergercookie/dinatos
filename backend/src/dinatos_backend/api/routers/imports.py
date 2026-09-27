from fastapi import APIRouter, Depends, HTTPException, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.api.deps import get_current_user
from dinatos_backend.db import get_db
from dinatos_backend.models.hevy_import import HevyImportKind
from dinatos_backend.models.user import User
from dinatos_backend.schemas.imports import HevyMeasurementImportResult, HevyWorkoutImportResult
from dinatos_backend.services.hevy_import import (
    find_previous_import,
    hash_csv_content,
    import_hevy_measurements,
    import_hevy_workouts,
    record_import,
)

router = APIRouter(prefix="/imports/hevy", tags=["imports"])


async def _reject_if_already_imported(
    db: AsyncSession, owner_id: int, kind: HevyImportKind, content_hash: str, *, force: bool
) -> None:
    if force:
        return
    previous = await find_previous_import(db, owner_id, kind, content_hash)
    if previous is not None:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            {
                "message": (
                    "a file with this exact content was already imported; pass "
                    "?force=true to import it again anyway"
                ),
                "previously_imported_at": previous.created_at.isoformat(),
                "previous_filename": previous.filename,
            },
        )


@router.post("/workouts", response_model=HevyWorkoutImportResult)
async def import_workouts(
    file: UploadFile,
    force: bool = False,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> HevyWorkoutImportResult:
    """Upload Hevy's "Workout Data" CSV export (Settings -> Export).

    Importing the exact same file content again is rejected with 409 --
    Hevy names every export the same, so filename can't tell duplicates
    apart -- unless `force=true`.
    """
    content = (await file.read()).decode("utf-8-sig")
    content_hash = hash_csv_content(content)
    await _reject_if_already_imported(
        db, user.id, HevyImportKind.workouts, content_hash, force=force
    )

    result = await import_hevy_workouts(db, user.id, content)
    await record_import(
        db,
        user.id,
        HevyImportKind.workouts,
        content_hash,
        file.filename,
        activities_created=result.activities_created,
        exercises_created=result.exercises_created,
    )
    return result


@router.post("/measurements", response_model=HevyMeasurementImportResult)
async def import_measurements(
    file: UploadFile,
    force: bool = False,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> HevyMeasurementImportResult:
    """Upload Hevy's "Measurement Data" CSV export (Settings -> Export).

    Importing the exact same file content again is rejected with 409 unless
    `force=true`.
    """
    content = (await file.read()).decode("utf-8-sig")
    content_hash = hash_csv_content(content)
    await _reject_if_already_imported(
        db, user.id, HevyImportKind.measurements, content_hash, force=force
    )

    result = await import_hevy_measurements(db, user.id, content)
    await record_import(
        db,
        user.id,
        HevyImportKind.measurements,
        content_hash,
        file.filename,
        measurements_created=result.measurements_created,
    )
    return result
