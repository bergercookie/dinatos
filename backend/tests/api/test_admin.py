from collections.abc import Iterator

import pytest
from httpx2 import AsyncClient

from dinatos_backend.config import Settings

_PASSWORD = "hunter22"


@pytest.fixture
def registration_disabled(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    monkeypatch.setattr(
        "dinatos_backend.services.auth.get_settings",
        lambda: Settings(allow_registration=False),
    )
    yield


async def _register(client: AsyncClient, email: str) -> dict[str, str]:
    await client.post("/auth/register", json={"email": email, "password": _PASSWORD})
    login = await client.post("/auth/login", json={"email": email, "password": _PASSWORD})
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


async def test_auth_config_reports_registration_enabled_by_default(
    anonymous_client: AsyncClient,
) -> None:
    response = await anonymous_client.get("/auth/config")
    assert response.status_code == 200
    assert response.json() == {"registration_enabled": True}


@pytest.mark.usefixtures("registration_disabled")
async def test_disabled_registration_still_allows_the_very_first_account(
    anonymous_client: AsyncClient,
) -> None:
    assert (await anonymous_client.get("/auth/config")).json() == {"registration_enabled": True}
    response = await anonymous_client.post(
        "/auth/register", json={"email": "first@example.com", "password": _PASSWORD}
    )
    assert response.status_code == 201
    assert response.json()["is_admin"] is True


@pytest.mark.usefixtures("registration_disabled")
async def test_disabled_registration_rejects_later_accounts(anonymous_client: AsyncClient) -> None:
    await _register(anonymous_client, "first@example.com")

    assert (await anonymous_client.get("/auth/config")).json() == {"registration_enabled": False}
    response = await anonymous_client.post(
        "/auth/register", json={"email": "second@example.com", "password": _PASSWORD}
    )
    assert response.status_code == 403


@pytest.mark.usefixtures("registration_disabled")
async def test_admin_can_create_accounts_while_registration_is_disabled(
    anonymous_client: AsyncClient,
) -> None:
    admin = await _register(anonymous_client, "admin@example.com")

    created = await anonymous_client.post(
        "/admin/users",
        json={"email": "member@example.com", "password": _PASSWORD},
        headers=admin,
    )
    assert created.status_code == 201
    assert created.json()["is_admin"] is False

    login = await anonymous_client.post(
        "/auth/login", json={"email": "member@example.com", "password": _PASSWORD}
    )
    assert login.status_code == 200


async def test_admin_can_create_another_admin(anonymous_client: AsyncClient) -> None:
    admin = await _register(anonymous_client, "admin@example.com")
    created = await anonymous_client.post(
        "/admin/users",
        json={"email": "co@example.com", "password": _PASSWORD, "is_admin": True},
        headers=admin,
    )
    assert created.status_code == 201
    assert created.json()["is_admin"] is True


async def test_admin_create_rejects_a_duplicate_email(anonymous_client: AsyncClient) -> None:
    admin = await _register(anonymous_client, "admin@example.com")
    response = await anonymous_client.post(
        "/admin/users",
        json={"email": "admin@example.com", "password": _PASSWORD},
        headers=admin,
    )
    assert response.status_code == 409


async def test_admin_can_list_users(anonymous_client: AsyncClient) -> None:
    admin = await _register(anonymous_client, "admin@example.com")
    await _register(anonymous_client, "member@example.com")
    response = await anonymous_client.get("/admin/users", headers=admin)
    assert response.status_code == 200
    assert [u["email"] for u in response.json()] == ["admin@example.com", "member@example.com"]


async def test_non_admin_cannot_use_admin_endpoints(anonymous_client: AsyncClient) -> None:
    await _register(anonymous_client, "admin@example.com")
    member = await _register(anonymous_client, "member@example.com")

    listing = await anonymous_client.get("/admin/users", headers=member)
    creating = await anonymous_client.post(
        "/admin/users",
        json={"email": "x@example.com", "password": _PASSWORD},
        headers=member,
    )
    assert listing.status_code == 403
    assert creating.status_code == 403


async def test_admin_endpoints_require_a_token(anonymous_client: AsyncClient) -> None:
    assert (await anonymous_client.get("/admin/users")).status_code in {401, 403}
