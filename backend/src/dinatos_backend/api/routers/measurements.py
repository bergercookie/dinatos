from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.api.deps import get_current_user
from dinatos_backend.db import get_db
from dinatos_backend.models.measurement import BodyMeasurement
from dinatos_backend.models.user import User
from dinatos_backend.schemas.measurement import BodyMeasurementCreate, BodyMeasurementRead

router = APIRouter(prefix="/measurements", tags=["measurements"])


async def _get_or_404(db: AsyncSession, owner_id: int, measurement_id: int) -> BodyMeasurement:
    result = await db.execute(
        select(BodyMeasurement).where(
            BodyMeasurement.id == measurement_id, BodyMeasurement.owner_id == owner_id
        )
    )
    measurement = result.scalar_one_or_none()
    if measurement is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "measurement not found")
    return measurement


@router.get("", response_model=list[BodyMeasurementRead])
async def list_measurements(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> list[BodyMeasurement]:
    result = await db.execute(
        select(BodyMeasurement)
        .where(BodyMeasurement.owner_id == user.id)
        .order_by(BodyMeasurement.measured_at)
    )
    return list(result.scalars())


@router.post("", response_model=BodyMeasurementRead, status_code=status.HTTP_201_CREATED)
async def create_measurement(
    payload: BodyMeasurementCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> BodyMeasurement:
    measurement = BodyMeasurement(owner_id=user.id, **payload.model_dump())
    db.add(measurement)
    await db.commit()
    await db.refresh(measurement)
    return measurement


@router.get("/{measurement_id}", response_model=BodyMeasurementRead)
async def get_measurement(
    measurement_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> BodyMeasurement:
    return await _get_or_404(db, user.id, measurement_id)


@router.put("/{measurement_id}", response_model=BodyMeasurementRead)
async def replace_measurement(
    measurement_id: int,
    payload: BodyMeasurementCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> BodyMeasurement:
    measurement = await _get_or_404(db, user.id, measurement_id)
    for field, value in payload.model_dump().items():
        setattr(measurement, field, value)
    await db.commit()
    await db.refresh(measurement)
    return measurement


@router.delete("/{measurement_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_measurement(
    measurement_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> None:
    measurement = await _get_or_404(db, user.id, measurement_id)
    await db.delete(measurement)
    await db.commit()
