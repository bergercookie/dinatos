"""API keys: shown once, usable like a login, and unable to manage themselves."""

import pytest
from httpx2 import AsyncClient

from backup_seed import Account, register
from dinatos_backend.services.api_keys import MAX_KEYS_PER_USER


async def _create(client: AsyncClient, name: str = "My MCP") -> dict[str, str]:
    response = await client.post("/api-keys", json={"name": name})
    assert response.status_code == 201, response.text
    body: dict[str, str] = response.json()
    return body


def _as_key(key: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {key}"}


async def test_the_key_is_shown_once_and_only_its_tail_afterwards(client: AsyncClient) -> None:
    created = await _create(client, "  Laptop MCP  ")
    assert created["key"].startswith("dnk_")
    assert created["name"] == "Laptop MCP"
    assert created["suffix"] == created["key"][-3:]

    listed = (await client.get("/api-keys")).json()
    assert [(k["name"], k["suffix"]) for k in listed] == [("Laptop MCP", created["suffix"])]
    assert "key" not in listed[0]
    assert created["key"] not in (await client.get("/api-keys")).text


async def test_a_blank_name_is_rejected(client: AsyncClient) -> None:
    assert (await client.post("/api-keys", json={"name": "   "})).status_code == 422
    assert (await client.post("/api-keys", json={"name": ""})).status_code == 422
    assert (await client.post("/api-keys", json={})).status_code == 422


async def test_a_key_authenticates_like_a_login_and_records_its_use(client: AsyncClient) -> None:
    created = await _create(client)
    assert (await client.get("/api-keys")).json()[0]["last_used_at"] is None

    exercises = await client.get("/exercises", headers=_as_key(created["key"]))
    assert exercises.status_code == 200
    assert (await client.get("/routines", headers=_as_key(created["key"]))).status_code == 200
    assert (await client.get("/api-keys")).json()[0]["last_used_at"] is not None


async def test_a_key_acts_as_its_own_user(
    client: AsyncClient, anonymous_client: AsyncClient
) -> None:
    mine = await _create(client)
    other = await register(anonymous_client, "other@example.com")
    await anonymous_client.post(
        "/routines", json={"name": "Other's routine", "exercises": []}, headers=other.headers
    )
    names = [
        r["name"] for r in (await client.get("/routines", headers=_as_key(mine["key"]))).json()
    ]
    assert "Other's routine" not in names


@pytest.mark.parametrize("token", ["dnk_nonsense", "dnk_", "nonsense"])
async def test_an_unknown_key_is_rejected(client: AsyncClient, token: str) -> None:
    assert (await client.get("/exercises", headers=_as_key(token))).status_code == 401


async def test_a_key_cannot_manage_keys_log_out_or_administer(client: AsyncClient) -> None:
    key = (await _create(client))["key"]
    headers = _as_key(key)
    assert (await client.get("/api-keys", headers=headers)).status_code == 401
    assert (await client.post("/api-keys", json={"name": "x"}, headers=headers)).status_code == 401
    assert (await client.delete("/api-keys/1", headers=headers)).status_code == 401
    assert (await client.post("/auth/logout", headers=headers)).status_code == 401
    # The first account is an admin, but a key still is not a session.
    assert (await client.get("/admin/users", headers=headers)).status_code == 401
    assert (await client.get("/admin/backup", headers=headers)).status_code == 401


async def test_deleting_a_key_revokes_it(client: AsyncClient) -> None:
    created = await _create(client)
    assert (await client.delete(f"/api-keys/{created['id']}")).status_code == 204
    assert (await client.get("/exercises", headers=_as_key(created["key"]))).status_code == 401
    assert (await client.get("/api-keys")).json() == []
    assert (await client.delete(f"/api-keys/{created['id']}")).status_code == 404


async def test_keys_are_private_to_their_owner(
    client: AsyncClient, anonymous_client: AsyncClient
) -> None:
    created = await _create(client)
    other: Account = await register(anonymous_client, "other@example.com")
    assert (await anonymous_client.get("/api-keys", headers=other.headers)).json() == []
    response = await anonymous_client.delete(f"/api-keys/{created['id']}", headers=other.headers)
    assert response.status_code == 404
    assert (await client.get("/exercises", headers=_as_key(created["key"]))).status_code == 200


async def test_there_is_a_cap_on_keys_per_account(client: AsyncClient) -> None:
    for i in range(MAX_KEYS_PER_USER):
        await _create(client, f"key {i}")
    assert (await client.post("/api-keys", json={"name": "one too many"})).status_code == 409


async def test_requests_without_a_login_cannot_create_keys(anonymous_client: AsyncClient) -> None:
    anonymous_client.headers.pop("Authorization", None)
    assert (await anonymous_client.post("/api-keys", json={"name": "x"})).status_code in {401, 403}
