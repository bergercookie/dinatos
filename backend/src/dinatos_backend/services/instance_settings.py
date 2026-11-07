"""Server-wide switches that an admin turns on and off from the app, stored in
the single `instance_settings` row.

An operator can pin a switch with its environment variable instead. The
variable then wins, the stored value is ignored, the app refuses to change the
switch (it shows it as locked), and the server logs a warning at startup.
"Pinned" means the variable is set at all, to `true` or `false`: whether it was
set is read from pydantic's `model_fields_set`, since a default of `True`
cannot tell "unset" from "set to true". An empty value counts as unset
(`Settings.env_ignore_empty`), which is how docker-compose passes an unset one.
"""

import logging
from dataclasses import dataclass
from typing import Literal

from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.config import get_settings
from dinatos_backend.models.instance_settings import InstanceSettings

logger = logging.getLogger(__name__)

# The switch's name is both the `Settings` field and the `instance_settings`
# column. Every switch is on until somebody turns it off.
Switch = Literal["allow_registration", "mcp_enabled"]

ENV_VARS: dict[Switch, str] = {
    "allow_registration": "DINATOS_ALLOW_REGISTRATION",
    "mcp_enabled": "DINATOS_MCP_ENABLED",
}

# What the startup warning calls each switch.
_LABELS: dict[Switch, str] = {
    "allow_registration": "registration",
    "mcp_enabled": "the MCP server",
}

_ROW_ID = 1


class SwitchLockedError(Exception):
    """The environment pins this switch, so the app cannot change it."""

    def __init__(self, switch: Switch) -> None:
        super().__init__(switch)
        self.switch = switch
        self.env_var = ENV_VARS[switch]


@dataclass(frozen=True)
class SwitchState:
    enabled: bool
    # True when the switch's environment variable is set: `enabled` is its value.
    locked: bool


def pinned_by_env(switch: Switch) -> bool | None:
    """The environment's value for `switch`, or `None` if its variable is unset."""
    settings = get_settings()
    if switch in settings.model_fields_set:
        value: bool = getattr(settings, switch)
        return value
    return None


async def get_switch(db: AsyncSession, switch: Switch) -> SwitchState:
    pinned = pinned_by_env(switch)
    if pinned is not None:
        return SwitchState(enabled=pinned, locked=True)
    row = await db.get(InstanceSettings, _ROW_ID)
    stored: bool | None = getattr(row, switch) if row is not None else None
    # Never chosen: the switch stays on, as it always was.
    return SwitchState(enabled=True if stored is None else stored, locked=False)


async def set_switch(db: AsyncSession, switch: Switch, enabled: bool) -> SwitchState:
    if pinned_by_env(switch) is not None:
        raise SwitchLockedError(switch)
    row = await db.get(InstanceSettings, _ROW_ID)
    if row is None:
        row = InstanceSettings(id=_ROW_ID)
        db.add(row)
    setattr(row, switch, enabled)
    await db.commit()
    return SwitchState(enabled=enabled, locked=False)


def warn_about_pinned_switches() -> None:
    """One startup warning (stderr) for each switch its variable overrides."""
    for switch, env_var in ENV_VARS.items():
        pinned = pinned_by_env(switch)
        if pinned is not None:
            logger.warning(
                "%s is set to %s: %s follows it, and the Administration screen cannot "
                "change it. Unset %s and restart to manage %s from the app instead.",
                env_var,
                str(pinned).lower(),
                _LABELS[switch],
                env_var,
                _LABELS[switch],
            )
