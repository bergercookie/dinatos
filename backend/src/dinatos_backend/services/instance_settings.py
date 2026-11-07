"""Server-wide options that an admin changes from the app, stored in the
single `instance_settings` row.

An operator can pin an option with an environment variable instead. The
variable then wins, the stored value is ignored, and the app refuses to change
the option (it shows it as locked). "Pinned" means the variable is set at all,
to `true` or `false`: whether it was set is read from pydantic's
`model_fields_set`, since the default `True` cannot tell "unset" from "set to
true". An empty value counts as unset (`Settings.env_ignore_empty`).
"""

import logging
from dataclasses import dataclass

from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.config import get_settings
from dinatos_backend.models.instance_settings import InstanceSettings

logger = logging.getLogger(__name__)

REGISTRATION_ENV_VAR = "DINATOS_ALLOW_REGISTRATION"
_ROW_ID = 1


class RegistrationLockedError(Exception):
    """The environment pins `allow_registration`, so the app cannot change it."""


@dataclass(frozen=True)
class RegistrationSetting:
    allowed: bool
    # True when `DINATOS_ALLOW_REGISTRATION` is set: `allowed` is its value.
    locked: bool


def registration_pinned_by_env() -> bool | None:
    """The environment's value for `allow_registration`, or `None` if unset."""
    settings = get_settings()
    if "allow_registration" in settings.model_fields_set:
        return settings.allow_registration
    return None


async def get_registration_setting(db: AsyncSession) -> RegistrationSetting:
    pinned = registration_pinned_by_env()
    if pinned is not None:
        return RegistrationSetting(allowed=pinned, locked=True)
    row = await db.get(InstanceSettings, _ROW_ID)
    stored = row.allow_registration if row is not None else None
    # Never chosen: registration stays open, as it always was.
    return RegistrationSetting(allowed=True if stored is None else stored, locked=False)


async def set_allow_registration(db: AsyncSession, allowed: bool) -> RegistrationSetting:
    if registration_pinned_by_env() is not None:
        raise RegistrationLockedError
    row = await db.get(InstanceSettings, _ROW_ID)
    if row is None:
        row = InstanceSettings(id=_ROW_ID)
        db.add(row)
    row.allow_registration = allowed
    await db.commit()
    return RegistrationSetting(allowed=allowed, locked=False)


def warn_if_registration_pinned() -> None:
    """Startup warning (stderr) that the environment overrides the admin option."""
    pinned = registration_pinned_by_env()
    if pinned is not None:
        logger.warning(
            "%s is set to %s: registration follows it, and the Administration screen "
            "cannot change it. Unset %s and restart to manage registration from the app.",
            REGISTRATION_ENV_VAR,
            str(pinned).lower(),
            REGISTRATION_ENV_VAR,
        )
