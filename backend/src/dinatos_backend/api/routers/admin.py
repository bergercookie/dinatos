"""Account administration -- admin-only, regardless of whether
self-registration (`DINATOS_ALLOW_REGISTRATION`) is enabled.
"""

from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, Depends, Form, HTTPException, Request, Response, UploadFile, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.api.deps import get_current_session, require_admin
from dinatos_backend.db import get_db
from dinatos_backend.models.auth_session import AuthSession
from dinatos_backend.models.user import User
from dinatos_backend.schemas.auth import AdminUserCreate, UserRead
from dinatos_backend.schemas.backup import BackupRestoreResult, FullBackup
from dinatos_backend.services.auth import EmailAlreadyRegisteredError, create_user
from dinatos_backend.services.backup import (
    BackupInvalidError,
    export_backup,
    parse_backup,
    restore_backup,
)

# A backup holds the whole server; far more than any real instance's, but a
# bound all the same so an upload cannot exhaust memory.
_MAX_BACKUP_BYTES = 256 * 1024 * 1024

router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(require_admin)])


@router.get("/users", response_model=list[UserRead])
async def list_users(db: AsyncSession = Depends(get_db)) -> list[User]:
    result = await db.execute(select(User).order_by(User.id))
    return list(result.scalars())


@router.post("/users", response_model=UserRead, status_code=status.HTTP_201_CREATED)
async def create_account(payload: AdminUserCreate, db: AsyncSession = Depends(get_db)) -> User:
    try:
        return await create_user(db, payload.email, payload.password, is_admin=payload.is_admin)
    except EmailAlreadyRegisteredError as error:
        raise HTTPException(status.HTTP_409_CONFLICT, "email already registered") from error


@router.get("/backup", response_model=FullBackup)
async def download_backup(
    request: Request, response: Response, db: AsyncSession = Depends(get_db)
) -> FullBackup:
    """Everything on the server as one versioned JSON document: all accounts
    (**including password hashes and stored API keys -- treat the file as a
    secret**), the exercise catalog, routines, activities, measurements and
    Hevy import records. Login sessions are deliberately not included.
    """
    stamp = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
    response.headers["Content-Disposition"] = f'attachment; filename="dinatos-backup-{stamp}.json"'
    return await export_backup(db, request.app.version)


@router.post("/backup/restore", response_model=BackupRestoreResult)
async def restore_from_backup(
    file: UploadFile,
    confirm: Annotated[bool, Form()] = False,
    user: User = Depends(require_admin),
    session: AuthSession = Depends(get_current_session),
    db: AsyncSession = Depends(get_db),
) -> BackupRestoreResult:
    """**Replaces the entire server state** with a document from `GET
    /admin/backup`: every existing row is deleted first, in one transaction.
    Requires the form field `confirm=true`. An invalid document is a 422 and
    changes nothing. All login sessions end except the caller's own, which
    survives only if the backup contains an account with the caller's id and
    email (`session_kept` in the response says which happened).
    """
    if not confirm:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "restoring replaces all data on this server; resend with confirm=true",
        )
    content = await file.read(_MAX_BACKUP_BYTES + 1)
    if len(content) > _MAX_BACKUP_BYTES:
        raise HTTPException(status.HTTP_413_CONTENT_TOO_LARGE, "backup file too large")
    try:
        return await restore_backup(db, parse_backup(content), user, session)
    except BackupInvalidError as error:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, error.problems) from error
