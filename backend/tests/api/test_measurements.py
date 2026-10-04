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


async def test_smart_scale_fields_round_trip(client: AsyncClient) -> None:
    scale = {
        "muscle_mass_kg": 55.1,
        "bone_mass_kg": 2.9,
        "bmi": 22.4,
        "dci_kcal": 2410,
        "metabolic_age": 27,
        "water_percent": 57.5,
        "visceral_fat": 6,
        "right_arm_fat_percent": 12.1,
        "right_arm_muscle_kg": 3.2,
        "left_arm_fat_percent": 12.4,
        "left_arm_muscle_kg": 3.1,
        "right_leg_fat_percent": 14.0,
        "right_leg_muscle_kg": 9.4,
        "left_leg_fat_percent": 14.2,
        "left_leg_muscle_kg": 9.3,
        "trunk_fat_percent": 16.3,
        "trunk_muscle_kg": 27.8,
    }
    created = await client.post(
        "/measurements", json={"measured_at": "2026-01-01T00:00:00Z", "weight_kg": 70, **scale}
    )
    assert created.status_code == 201
    fetched = (await client.get(f"/measurements/{created.json()['id']}")).json()
    assert {name: fetched[name] for name in scale} == scale
    # Whole-number fields stay integers on the wire.
    assert isinstance(fetched["dci_kcal"], int)
    assert isinstance(fetched["metabolic_age"], int)

    # An entry without them (a tape-measure session) leaves them null.
    plain = await client.post(
        "/measurements", json={"measured_at": "2026-01-02T00:00:00Z", "waist_cm": 80}
    )
    assert plain.json()["muscle_mass_kg"] is None
    assert plain.json()["trunk_fat_percent"] is None
