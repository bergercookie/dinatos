"""Full server backup: export, wipe/mutate, restore, export again -- and what
a restore must refuse or keep. Admin only.
"""

import json
from typing import Any

import pytest
from httpx2 import AsyncClient
from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from backup_seed import PASSWORD, Seeded, login, populate, post
from dinatos_backend.models.base import Base

pytestmark = pytest.mark.usefixtures("seeded")


async def _export(client: AsyncClient, headers: dict[str, str] | None = None) -> dict[str, Any]:
    response = await client.get("/admin/backup", headers=headers)
    assert response.status_code == 200, response.text
    document: dict[str, Any] = response.json()
    return document


def _comparable(document: dict[str, Any]) -> dict[str, Any]:
    """Everything except when the export was made."""
    return {key: value for key, value in document.items() if key != "exported_at"}


async def _restore(
    client: AsyncClient,
    document: dict[str, Any] | bytes,
    *,
    confirm: bool = True,
    headers: dict[str, str] | None = None,
) -> Any:
    content = document if isinstance(document, bytes) else json.dumps(document).encode()
    return await client.post(
        "/admin/backup/restore",
        files={"file": ("backup.json", content, "application/json")},
        data={"confirm": "true"} if confirm else {},
        headers=headers,
    )


@pytest.fixture
async def seeded(client: AsyncClient, session_factory: async_sessionmaker[AsyncSession]) -> Seeded:
    return await populate(client, session_factory)


async def test_export_document_shape(client: AsyncClient) -> None:
    response = await client.get("/admin/backup")
    assert response.status_code == 200
    assert "attachment" in response.headers["content-disposition"]
    document = response.json()

    assert document["format"] == "dinatos-backup"
    assert document["format_version"] == 1
    assert document["app_version"]
    assert document["exported_at"]
    # Ephemeral sessions are deliberately absent...
    assert "auth_sessions" not in document["tables"]
    tables = document["tables"]
    # ...while everything else, secrets included, is there.
    assert {user["email"] for user in tables["users"]} == {
        "test@example.com",
        "alice@example.com",
        "bob@example.com",
    }
    assert all(user["password_hash"].startswith("$argon2") for user in tables["users"])
    assert {profile["workoutx_api_key"] for profile in tables["user_profile"]} >= {
        "alice-secret-key"
    }
    assert len(tables["routines"]) == 4
    assert len(tables["activities"]) == 3
    assert len(tables["body_measurements"]) == 3
    assert len(tables["hevy_import_records"]) == 1
    assert {row["name"] for row in tables["exercises"]} == {
        "Bench Press",
        "Hill Sprint",
        "Bob's Curl",
    }
    assert tables["activity_sets"][0]["set_type"] in {"normal", "dropset", "warmup", "failure"}


async def test_restore_after_mutation_brings_everything_back(
    client: AsyncClient, seeded: Seeded
) -> None:
    before = await _export(client)

    # Mutate: change, delete and add across several tables.
    routines = (await client.get("/routines", headers=seeded.alice.headers)).json()
    for routine in routines:
        await client.delete(f"/routines/{routine['id']}", headers=seeded.alice.headers)
    await client.patch("/profile", json={"workoutx_api_key": ""}, headers=seeded.alice.headers)
    await client.post("/admin/users", json={"email": "mallory@example.com", "password": PASSWORD})
    await post(client, seeded.bob, "/measurements", {"measured_at": "2027-01-01T00:00:00Z"})
    assert _comparable(await _export(client)) != _comparable(before)

    response = await _restore(client, before)
    assert response.status_code == 200, response.text
    result = response.json()
    assert result["session_kept"] is True
    assert result["rows"]["users"] == 3
    assert result["rows"]["routines"] == 4

    after = await _export(client)
    assert _comparable(after) == _comparable(before)

    # Functionally back: original passwords log in again, the stray account is gone.
    alice = await login(client, "alice@example.com")
    assert (await client.get("/routines", headers=alice.headers)).status_code == 200
    assert len((await client.get("/routines", headers=alice.headers)).json()) == 2
    assert (
        await client.post(
            "/auth/login",
            json={"email": "mallory@example.com", "password": PASSWORD},
            headers={"Authorization": ""},
        )
    ).status_code == 401
    # Other accounts' old sessions did not survive; only the caller's did.
    assert (await client.get("/routines", headers=seeded.alice.headers)).status_code == 401
    assert (await client.get("/routines", headers=seeded.bob.headers)).status_code == 401

    # New rows after a restore must not collide with restored ids.
    created = await post(client, alice, "/routines", {"name": "After", "exercises": []})
    assert created["id"] > max(row["id"] for row in before["tables"]["routines"])


async def test_restore_into_a_wiped_server_with_a_different_admin_logs_the_caller_out(
    client: AsyncClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    backup = await _export(client)

    async with session_factory() as session:
        for table in reversed(Base.metadata.sorted_tables):
            await session.execute(delete(table))
        await session.commit()
    # A brand new instance: its first account (id 1 again, but a different
    # email than the backup's id 1) becomes admin.
    await client.post(
        "/auth/register",
        json={"email": "new-admin@example.com", "password": PASSWORD},
        headers={"Authorization": ""},
    )
    new_admin = await login(client, "new-admin@example.com")

    response = await _restore(client, backup, headers=new_admin.headers)
    assert response.status_code == 200, response.text
    # Same id, different person: the session must not carry over.
    assert response.json()["session_kept"] is False
    assert (await client.get("/auth/me", headers=new_admin.headers)).status_code == 401

    admin = await login(client, "test@example.com")
    assert _comparable(await _export(client, admin.headers)) == _comparable(backup)
    alice = await login(client, "alice@example.com")
    assert len((await client.get("/activities", headers=alice.headers)).json()) == 2


async def test_restore_drops_the_callers_session_if_their_account_is_not_in_the_backup(
    client: AsyncClient,
) -> None:
    backup = await _export(client)
    # An admin whose account the backup predates.
    await client.post(
        "/admin/users",
        json={"email": "late@example.com", "password": PASSWORD, "is_admin": True},
    )
    late = await login(client, "late@example.com")

    response = await _restore(client, backup, headers=late.headers)
    assert response.status_code == 200
    assert response.json()["session_kept"] is False
    assert (await client.get("/auth/me", headers=late.headers)).status_code == 401


async def test_restore_requires_admin_and_authentication(
    client: AsyncClient, seeded: Seeded
) -> None:
    backup = await _export(client)

    assert (await client.get("/admin/backup", headers=seeded.alice.headers)).status_code == 403
    assert (await _restore(client, backup, headers=seeded.alice.headers)).status_code == 403
    assert (await client.get("/admin/backup", headers={"Authorization": ""})).status_code == 401
    assert (await _restore(client, backup, headers={"Authorization": ""})).status_code == 401
    # Nothing changed.
    assert _comparable(await _export(client)) == _comparable(backup)


async def test_restore_requires_explicit_confirmation(client: AsyncClient) -> None:
    backup = await _export(client)
    await client.delete(
        f"/routines/{(await client.get('/routines')).json()[0]['id']}",
    )
    mutated = await _export(client)

    response = await _restore(client, backup, confirm=False)
    assert response.status_code == 400
    assert "confirm" in response.json()["detail"]
    assert _comparable(await _export(client)) == _comparable(mutated)


async def test_oversized_upload_is_rejected(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr("dinatos_backend.api.routers.admin._MAX_BACKUP_BYTES", 10)
    response = await _restore(client, await _export(client))
    assert response.status_code == 413


def _tweak(path: str, value: Any) -> Any:
    """A mutation of a valid document: 'table.index.column' set to `value`
    (or the column removed when `value` is `...`).
    """

    def apply(document: dict[str, Any]) -> None:
        table, index, column = path.split(".")
        row = document["tables"][table][int(index)]
        if value is ...:
            del row[column]
        else:
            row[column] = value

    return apply


def _drop_table(document: dict[str, Any]) -> None:
    del document["tables"]["routines"]


def _unknown_table(document: dict[str, Any]) -> None:
    document["tables"]["mystery"] = []


def _duplicate_user(document: dict[str, Any]) -> None:
    document["tables"]["users"].append({**document["tables"]["users"][1], "id": 99})


def _row_not_object(document: dict[str, Any]) -> None:
    document["tables"]["routines"][0] = 5


def _tables_not_object(document: dict[str, Any]) -> None:
    document["tables"] = []


def _no_admin(document: dict[str, Any]) -> None:
    for user in document["tables"]["users"]:
        user["is_admin"] = False


def _duplicate_pk(document: dict[str, Any]) -> None:
    document["tables"]["routines"].append(dict(document["tables"]["routines"][0]))


def _wrong_format(document: dict[str, Any]) -> None:
    document["format"] = "something-else"


def _wrong_version(document: dict[str, Any]) -> None:
    document["format_version"] = 2


def _bool_version(document: dict[str, Any]) -> None:
    document["format_version"] = True


@pytest.mark.parametrize(
    ("mutate", "message"),
    [
        (_wrong_format, "not a Dinatos backup"),
        (_wrong_version, "unsupported format_version"),
        (_bool_version, "unsupported format_version"),
        (_tables_not_object, "'tables' must be an object"),
        (_drop_table, "missing or not a list"),
        (_unknown_table, "unknown table 'mystery'"),
        (_row_not_object, "must be an object"),
        (_tweak("routines.0.bogus", 1), "unknown column"),
        (_tweak("routines.0.name", ...), "missing column 'name'"),
        (_tweak("routines.0.name", None), "must not be null"),
        (_tweak("routines.0.name", 5), "must be of type str"),
        (_tweak("routines.0.name", "x" * 201), "longer than 200"),
        (_tweak("routines.0.id", True), "must be of type int"),
        (_tweak("users.0.is_admin", 1), "must be of type bool"),
        (_tweak("users.0.created_at", "yesterday"), "ISO 8601"),
        (_tweak("users.0.created_at", 12), "ISO 8601"),
        (_tweak("exercises.0.equipment", "jetpack"), "not a valid Equipment"),
        (_tweak("body_measurements.0.weight_kg", "heavy"), "finite number"),
        (_tweak("body_measurements.0.weight_kg", float("inf")), "finite number"),
        (_tweak("routines.0.owner_id", 12345), "has no matching users.id"),
        (_no_admin, "no admin account"),
        (_duplicate_pk, "duplicate primary key"),
    ],
)
async def test_invalid_documents_are_rejected_and_change_nothing(
    client: AsyncClient,
    mutate: Any,
    message: str,
) -> None:
    before = await _export(client)
    document = json.loads(json.dumps(before))
    mutate(document)

    response = await _restore(client, json.dumps(document, allow_nan=True).encode())

    assert response.status_code == 422, response.text
    assert message in json.dumps(response.json()["detail"])
    assert _comparable(await _export(client)) == _comparable(before)


@pytest.mark.parametrize("content", [b"", b"not json", b"\xff\xfe", b"[]", b'"x"'])
async def test_garbage_uploads_are_rejected_and_change_nothing(
    client: AsyncClient, content: bytes
) -> None:
    before = await _export(client)
    response = await _restore(client, content)
    assert response.status_code == 422
    assert _comparable(await _export(client)) == _comparable(before)


async def test_database_level_rejection_rolls_the_whole_restore_back(client: AsyncClient) -> None:
    """Passes every check the parser can make, but breaks a unique constraint
    (two accounts, one email) -- by then every table has already been
    emptied, and the transaction must put it all back.
    """
    before = await _export(client)
    document = json.loads(json.dumps(before))
    _duplicate_user(document)
    document["tables"]["users"][-1]["email"] = document["tables"]["users"][1]["email"]

    response = await _restore(client, document)

    assert response.status_code == 422
    assert "database rejected" in json.dumps(response.json()["detail"])
    assert _comparable(await _export(client)) == _comparable(before)
    assert (await client.get("/auth/me")).status_code == 200


async def test_backup_from_before_a_column_existed_still_restores(client: AsyncClient) -> None:
    """A column added since the backup was made is filled from its nullable /
    default, so adding one does not invalidate older backups.
    """
    before = await _export(client)
    document = json.loads(json.dumps(before))
    for row in document["tables"]["routines"]:
        del row["description"]  # nullable
    for row in document["tables"]["exercises"]:
        del row["tracks_weight"]  # not nullable, has a Python-side default

    response = await _restore(client, document)

    assert response.status_code == 200, response.text
    after = await _export(client)
    assert all(row["description"] is None for row in after["tables"]["routines"])
    assert all(row["tracks_weight"] is True for row in after["tables"]["exercises"])


async def test_restoring_a_nearly_empty_backup(client: AsyncClient) -> None:
    """Empty tables are fine -- only an admin account is required."""
    document = await _export(client)
    document["tables"] = {name: [] for name in document["tables"]}
    document["tables"]["users"] = [
        {
            "id": 1,
            "email": "test@example.com",
            "password_hash": "x",
            "is_admin": True,
            "created_at": "2026-01-01T00:00:00+00:00",
            "updated_at": "2026-01-01T00:00:00+00:00",
        }
    ]

    response = await _restore(client, document)

    assert response.status_code == 200, response.text
    assert response.json()["rows"]["routines"] == 0
    assert (await client.get("/routines")).json() == []
