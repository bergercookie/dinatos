"""The admin's registration switch, and the environment variable that locks it."""

import logging
from pathlib import Path

import pytest
from httpx2 import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.config import Settings
from dinatos_backend.services.instance_settings import (
    ENV_VARS,
    Switch,
    SwitchLockedError,
    pinned_by_env,
    set_switch,
    warn_about_pinned_switches,
)

REGISTRATION_ENV_VAR = ENV_VARS["allow_registration"]
MCP_ENV_VAR = ENV_VARS["mcp_enabled"]
_DEFAULTS = {
    "allow_registration": True,
    "allow_registration_locked": False,
    "mcp_enabled": True,
    "mcp_enabled_locked": False,
}

_PASSWORD = "hunter22"


def _pin(
    monkeypatch: pytest.MonkeyPatch, value: bool, switch: Switch = "allow_registration"
) -> None:
    """Behave as if the switch's variable (for example
    `DINATOS_ALLOW_REGISTRATION=<value>`) were set.
    """
    settings = (
        Settings(allow_registration=value)
        if switch == "allow_registration"
        else Settings(mcp_enabled=value)
    )
    monkeypatch.setattr("dinatos_backend.services.instance_settings.get_settings", lambda: settings)


async def _register(client: AsyncClient, email: str) -> dict[str, str]:
    await client.post("/auth/register", json={"email": email, "password": _PASSWORD})
    login = await client.post("/auth/login", json={"email": email, "password": _PASSWORD})
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


async def _can_register(client: AsyncClient, email: str) -> bool:
    response = await client.post("/auth/register", json={"email": email, "password": _PASSWORD})
    return response.status_code == 201


async def test_registration_is_open_and_unlocked_by_default(
    anonymous_client: AsyncClient,
) -> None:
    admin = await _register(anonymous_client, "admin@example.com")

    response = await anonymous_client.get("/admin/settings", headers=admin)

    assert response.status_code == 200
    assert response.json() == _DEFAULTS


async def test_admin_can_turn_registration_off_and_on(anonymous_client: AsyncClient) -> None:
    admin = await _register(anonymous_client, "admin@example.com")

    off = await anonymous_client.patch(
        "/admin/settings", json={"allow_registration": False}, headers=admin
    )
    assert off.status_code == 200
    assert off.json() == {**_DEFAULTS, "allow_registration": False}
    assert (await anonymous_client.get("/auth/config")).json()["registration_enabled"] is False
    assert not await _can_register(anonymous_client, "closed@example.com")

    on = await anonymous_client.patch(
        "/admin/settings", json={"allow_registration": True}, headers=admin
    )
    assert on.json()["allow_registration"] is True
    assert (await anonymous_client.get("/auth/config")).json()["registration_enabled"] is True
    assert await _can_register(anonymous_client, "open@example.com")


async def test_an_empty_update_changes_nothing(anonymous_client: AsyncClient) -> None:
    admin = await _register(anonymous_client, "admin@example.com")
    await anonymous_client.patch(
        "/admin/settings", json={"allow_registration": False}, headers=admin
    )

    response = await anonymous_client.patch("/admin/settings", json={}, headers=admin)

    assert response.json()["allow_registration"] is False


async def test_only_admins_can_read_or_change_the_settings(anonymous_client: AsyncClient) -> None:
    await _register(anonymous_client, "admin@example.com")
    member = await _register(anonymous_client, "member@example.com")

    read = await anonymous_client.get("/admin/settings", headers=member)
    write = await anonymous_client.patch(
        "/admin/settings", json={"allow_registration": False}, headers=member
    )

    assert read.status_code == 403
    assert write.status_code == 403
    assert (await anonymous_client.get("/admin/settings")).status_code == 401


@pytest.mark.parametrize("pinned", [True, False])
async def test_the_environment_variable_wins_and_locks_the_switch(
    anonymous_client: AsyncClient, monkeypatch: pytest.MonkeyPatch, pinned: bool
) -> None:
    admin = await _register(anonymous_client, "admin@example.com")
    _pin(monkeypatch, pinned)

    read = await anonymous_client.get("/admin/settings", headers=admin)
    write = await anonymous_client.patch(
        "/admin/settings", json={"allow_registration": not pinned}, headers=admin
    )

    assert read.json() == {
        **_DEFAULTS,
        "allow_registration": pinned,
        "allow_registration_locked": True,
    }
    assert write.status_code == 409
    assert REGISTRATION_ENV_VAR in write.json()["detail"]
    assert (await anonymous_client.get("/auth/config")).json()["registration_enabled"] is pinned
    assert await _can_register(anonymous_client, "new@example.com") is pinned


async def test_the_environment_variable_beats_a_stored_choice(
    anonymous_client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """An admin chose "off" while the variable was unset; the operator later
    pins it to "on". The variable wins, and clearing it restores the choice.
    """
    admin = await _register(anonymous_client, "admin@example.com")
    await anonymous_client.patch(
        "/admin/settings", json={"allow_registration": False}, headers=admin
    )
    with monkeypatch.context() as pinned:
        _pin(pinned, True)
        assert await _can_register(anonymous_client, "pinned@example.com")

    assert not await _can_register(anonymous_client, "cleared@example.com")


def test_an_unset_or_empty_variable_is_not_pinned(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.chdir(tmp_path)  # no stray .env
    monkeypatch.delenv(REGISTRATION_ENV_VAR, raising=False)
    assert "allow_registration" not in Settings().model_fields_set

    # docker-compose passes an unset variable on as an empty string.
    monkeypatch.setenv(REGISTRATION_ENV_VAR, "")
    assert "allow_registration" not in Settings().model_fields_set

    monkeypatch.setenv(REGISTRATION_ENV_VAR, "false")
    settings = Settings()
    assert "allow_registration" in settings.model_fields_set
    assert settings.allow_registration is False


def test_pinned_value_is_none_when_unset(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "dinatos_backend.services.instance_settings.get_settings", lambda: Settings()
    )
    assert pinned_by_env("allow_registration") is None
    assert pinned_by_env("mcp_enabled") is None


@pytest.mark.parametrize(("pinned", "word"), [(True, "true"), (False, "false")])
def test_startup_warns_when_the_variable_is_set(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture, pinned: bool, word: str
) -> None:
    _pin(monkeypatch, pinned)

    with caplog.at_level(logging.WARNING):
        warn_about_pinned_switches()

    assert len(caplog.records) == 1
    message = caplog.records[0].getMessage()
    assert REGISTRATION_ENV_VAR in message
    assert f"set to {word}" in message
    assert "Unset" in message


def test_startup_is_silent_when_the_variable_is_unset(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    monkeypatch.setattr(
        "dinatos_backend.services.instance_settings.get_settings", lambda: Settings()
    )

    with caplog.at_level(logging.WARNING):
        warn_about_pinned_switches()

    assert caplog.records == []


async def test_the_admin_choice_is_part_of_the_backup(anonymous_client: AsyncClient) -> None:
    admin = await _register(anonymous_client, "admin@example.com")
    await anonymous_client.patch(
        "/admin/settings", json={"allow_registration": False}, headers=admin
    )
    backup = (await anonymous_client.get("/admin/backup", headers=admin)).json()
    assert backup["tables"]["instance_settings"][0]["allow_registration"] is False


# -- The MCP server switch (`DINATOS_MCP_ENABLED`) works the same way.


async def test_admin_can_turn_the_mcp_server_off_and_on(anonymous_client: AsyncClient) -> None:
    admin = await _register(anonymous_client, "admin@example.com")

    off = await anonymous_client.patch(
        "/admin/settings", json={"mcp_enabled": False}, headers=admin
    )
    assert off.json() == {**_DEFAULTS, "mcp_enabled": False}
    assert (await anonymous_client.get("/auth/config")).json()["mcp_enabled"] is False

    on = await anonymous_client.patch("/admin/settings", json={"mcp_enabled": True}, headers=admin)
    assert on.json() == _DEFAULTS
    assert (await anonymous_client.get("/auth/config")).json()["mcp_enabled"] is True


@pytest.mark.parametrize("pinned", [True, False])
async def test_the_mcp_variable_wins_and_locks_its_switch(
    anonymous_client: AsyncClient, monkeypatch: pytest.MonkeyPatch, pinned: bool
) -> None:
    admin = await _register(anonymous_client, "admin@example.com")
    _pin(monkeypatch, pinned, "mcp_enabled")

    read = await anonymous_client.get("/admin/settings", headers=admin)
    write = await anonymous_client.patch(
        "/admin/settings", json={"mcp_enabled": not pinned}, headers=admin
    )

    assert read.json() == {**_DEFAULTS, "mcp_enabled": pinned, "mcp_enabled_locked": True}
    assert write.status_code == 409
    assert MCP_ENV_VAR in write.json()["detail"]
    assert (await anonymous_client.get("/auth/config")).json()["mcp_enabled"] is pinned


async def test_an_update_with_a_locked_switch_changes_nothing(
    anonymous_client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """All or nothing: registration is free to change, but MCP is pinned, so
    neither changes.
    """
    admin = await _register(anonymous_client, "admin@example.com")
    _pin(monkeypatch, True, "mcp_enabled")

    response = await anonymous_client.patch(
        "/admin/settings",
        json={"allow_registration": False, "mcp_enabled": False},
        headers=admin,
    )

    assert response.status_code == 409
    after = (await anonymous_client.get("/admin/settings", headers=admin)).json()
    assert after["allow_registration"] is True


def test_startup_warns_once_for_each_pinned_variable(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    monkeypatch.setattr(
        "dinatos_backend.services.instance_settings.get_settings",
        lambda: Settings(allow_registration=False, mcp_enabled=False),
    )

    with caplog.at_level(logging.WARNING):
        warn_about_pinned_switches()

    messages = [record.getMessage() for record in caplog.records]
    assert len(messages) == 2
    assert any(REGISTRATION_ENV_VAR in m and "registration" in m for m in messages)
    assert any(MCP_ENV_VAR in m and "the MCP server" in m for m in messages)


async def test_the_mcp_choice_is_part_of_the_backup(anonymous_client: AsyncClient) -> None:
    admin = await _register(anonymous_client, "admin@example.com")
    await anonymous_client.patch("/admin/settings", json={"mcp_enabled": False}, headers=admin)

    backup = (await anonymous_client.get("/admin/backup", headers=admin)).json()

    assert backup["tables"]["instance_settings"][0]["mcp_enabled"] is False


async def test_the_service_itself_refuses_a_pinned_switch(
    db: AsyncSession, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The router checks the lock first, but the service does not rely on it."""
    _pin(monkeypatch, True, "mcp_enabled")

    with pytest.raises(SwitchLockedError) as raised:
        await set_switch(db, "mcp_enabled", False)

    assert raised.value.switch == "mcp_enabled"
    assert raised.value.env_var == MCP_ENV_VAR
