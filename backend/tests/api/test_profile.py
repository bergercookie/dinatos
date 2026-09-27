from httpx import AsyncClient


async def test_read_profile_creates_it_on_first_access(client: AsyncClient) -> None:
    response = await client.get("/profile")
    assert response.status_code == 200
    assert response.json() == {"height_cm": None, "unit_system": "metric"}


async def test_update_profile(client: AsyncClient) -> None:
    response = await client.patch("/profile", json={"height_cm": 181.5, "unit_system": "imperial"})
    assert response.status_code == 200
    assert response.json() == {"height_cm": 181.5, "unit_system": "imperial"}

    # Persisted, not just echoed back.
    response = await client.get("/profile")
    assert response.json()["height_cm"] == 181.5
