import pytest
from httpx2 import AsyncClient


async def test_read_profile_creates_it_on_first_access(client: AsyncClient) -> None:
    response = await client.get("/profile")
    assert response.status_code == 200
    assert response.json() == {
        "height_cm": None,
        "unit_system": "metric",
        "has_workoutx_api_key": False,
    }


async def test_update_profile(client: AsyncClient) -> None:
    response = await client.patch("/profile", json={"height_cm": 181.5, "unit_system": "imperial"})
    assert response.status_code == 200
    assert response.json() == {
        "height_cm": 181.5,
        "unit_system": "imperial",
        "has_workoutx_api_key": False,
    }

    # Persisted, not just echoed back.
    response = await client.get("/profile")
    assert response.json()["height_cm"] == 181.5


async def test_workoutx_api_key_is_write_only(client: AsyncClient) -> None:
    response = await client.get("/profile")
    assert response.json()["has_workoutx_api_key"] is False

    response = await client.patch("/profile", json={"workoutx_api_key": "  wx_secret  "})
    assert response.status_code == 200
    assert response.json()["has_workoutx_api_key"] is True
    assert "workoutx_api_key" not in response.json()

    # Updating something else leaves the key alone.
    response = await client.patch("/profile", json={"height_cm": 170})
    assert response.json()["has_workoutx_api_key"] is True

    # A blank value clears it.
    response = await client.patch("/profile", json={"workoutx_api_key": "  "})
    assert response.json()["has_workoutx_api_key"] is False


async def test_tutorial_uses_the_callers_own_workoutx_key(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    from dinatos_backend.api import deps

    seen: list[str | None] = []

    def fake_for_key(api_key: str | None) -> _NoTutorial:
        seen.append(api_key)
        return _NoTutorial()

    monkeypatch.setattr(deps, "get_tutorial_provider_for_key", fake_for_key)
    exercise = await client.post("/exercises", json={"name": "Zottman Curl"})
    path = f"/exercises/{exercise.json()['id']}/tutorial"

    await client.get(path)
    await client.patch("/profile", json={"workoutx_api_key": "wx_mine"})
    await client.get(path)

    assert seen == [None, "wx_mine"]


class _NoTutorial:
    async def get_tutorial(self, _exercise_name: str) -> None:
        return None


async def test_gif_proxy_uses_the_callers_own_workoutx_key(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    import httpx2 as httpx

    from dinatos_backend.api import deps
    from dinatos_backend.services.tutorials.workoutx import WorkoutXProvider

    seen: list[str] = []

    def fake_for_key(api_key: str) -> WorkoutXProvider:
        seen.append(api_key)
        transport = httpx.MockTransport(lambda _request: httpx.Response(200, content=b"GIF89a"))
        return WorkoutXProvider(
            api_key,
            client=httpx.AsyncClient(transport=transport, base_url="https://api.test/v1"),
        )

    monkeypatch.setattr(deps, "get_workoutx_provider", fake_for_key)
    await client.patch("/profile", json={"workoutx_api_key": "wx_mine"})

    response = await client.get("/exercises/media/workoutx/0025.gif")

    assert response.status_code == 200
    assert seen == ["wx_mine"]
