from httpx2 import AsyncClient


async def test_create_and_list_measurements(client: AsyncClient) -> None:
    response = await client.post(
        "/measurements",
        json={"measured_at": "2026-01-01T00:00:00Z", "weight_kg": 68.2},
    )
    assert response.status_code == 201
    body = response.json()
    assert body["weight_kg"] == 68.2
    assert body["neck_cm"] is None

    response = await client.get("/measurements")
    assert response.status_code == 200
    assert len(response.json()) == 1


async def test_delete_measurement(client: AsyncClient) -> None:
    created = await client.post("/measurements", json={"measured_at": "2026-01-01T00:00:00Z"})
    measurement_id = created.json()["id"]

    response = await client.delete(f"/measurements/{measurement_id}")
    assert response.status_code == 204

    response = await client.get("/measurements")
    assert response.json() == []


async def test_delete_missing_measurement_is_404(client: AsyncClient) -> None:
    response = await client.delete("/measurements/999")
    assert response.status_code == 404


async def test_get_measurement(client: AsyncClient) -> None:
    created = await client.post(
        "/measurements",
        json={"measured_at": "2026-01-01T00:00:00Z", "weight_kg": 68.2},
    )
    measurement_id = created.json()["id"]

    response = await client.get(f"/measurements/{measurement_id}")
    assert response.status_code == 200
    assert response.json()["weight_kg"] == 68.2


async def test_get_missing_measurement_is_404(client: AsyncClient) -> None:
    response = await client.get("/measurements/999")
    assert response.status_code == 404


async def test_update_measurement(client: AsyncClient) -> None:
    created = await client.post(
        "/measurements",
        json={"measured_at": "2026-01-01T00:00:00Z", "weight_kg": 68.2},
    )
    measurement_id = created.json()["id"]

    response = await client.put(
        f"/measurements/{measurement_id}",
        json={"measured_at": "2026-01-02T00:00:00Z", "weight_kg": 70.0, "fat_percent": 15.0},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["weight_kg"] == 70.0
    assert body["fat_percent"] == 15.0

    response = await client.get(f"/measurements/{measurement_id}")
    assert response.json()["weight_kg"] == 70.0


async def test_update_missing_measurement_is_404(client: AsyncClient) -> None:
    response = await client.put("/measurements/999", json={"measured_at": "2026-01-01T00:00:00Z"})
    assert response.status_code == 404
