"""The admin's registration switch, and the environment variable that locks it."""

import logging
from pathlib import Path

import pytest
from httpx2 import AsyncClient

from dinatos_backend.config import Settings
from dinatos_backend.services.instance_settings import (
    REGISTRATION_ENV_VAR,
    registration_pinned_by_env,
    warn_if_registration_pinned,
)

_PASSWORD = "hunter22"


def _pin(monkeypatch: pytest.MonkeyPatch, value: bool) -> None:
    """Behave as if `DINATOS_ALLOW_REGISTRATION=<value>` were set."""
    monkeypatch.setattr(
        "dinatos_backend.services.instance_settings.get_settings",
        lambda: Settings(allow_registration=value),
    )


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
    assert response.json() == {"allow_registration": True, "allow_registration_locked": False}


async def test_admin_can_turn_registration_off_and_on(anonymous_client: AsyncClient) -> None:
    admin = await _register(anonymous_client, "admin@example.com")

    off = await anonymous_client.patch(
        "/admin/settings", json={"allow_registration": False}, headers=admin
    )
    assert off.status_code == 200
    assert off.json() == {"allow_registration": False, "allow_registration_locked": False}
    assert (await anonymous_client.get("/auth/config")).json() == {"registration_enabled": False}
    assert not await _can_register(anonymous_client, "closed@example.com")

    on = await anonymous_client.patch(
        "/admin/settings", json={"allow_registration": True}, headers=admin
    )
    assert on.json()["allow_registration"] is True
    assert (await anonymous_client.get("/auth/config")).json() == {"registration_enabled": True}
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

    assert read.json() == {"allow_registration": pinned, "allow_registration_locked": True}
    assert write.status_code == 409
    assert REGISTRATION_ENV_VAR in write.json()["detail"]
    assert (await anonymous_client.get("/auth/config")).json() == {"registration_enabled": pinned}
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
    assert registration_pinned_by_env() is None


@pytest.mark.parametrize(("pinned", "word"), [(True, "true"), (False, "false")])
def test_startup_warns_when_the_variable_is_set(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture, pinned: bool, word: str
) -> None:
    _pin(monkeypatch, pinned)

    with caplog.at_level(logging.WARNING):
        warn_if_registration_pinned()

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
        warn_if_registration_pinned()

    assert caplog.records == []


async def test_the_admin_choice_is_part_of_the_backup(anonymous_client: AsyncClient) -> None:
    admin = await _register(anonymous_client, "admin@example.com")
    await anonymous_client.patch(
        "/admin/settings", json={"allow_registration": False}, headers=admin
    )
    backup = (await anonymous_client.get("/admin/backup", headers=admin)).json()
    assert backup["tables"]["instance_settings"][0]["allow_registration"] is False
