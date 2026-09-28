from httpx import AsyncClient

_EMAIL = "session-test@example.com"
_PASSWORD = "hunter22"


async def test_register_creates_a_user(anonymous_client: AsyncClient) -> None:
    response = await anonymous_client.post(
        "/auth/register", json={"email": "first@example.com", "password": "hunter22"}
    )
    assert response.status_code == 201
    body = response.json()
    assert body["email"] == "first@example.com"
    assert "password" not in body
    assert "password_hash" not in body


async def test_first_user_is_admin_the_rest_are_not(anonymous_client: AsyncClient) -> None:
    first = await anonymous_client.post(
        "/auth/register", json={"email": "first@example.com", "password": "hunter22"}
    )
    second = await anonymous_client.post(
        "/auth/register", json={"email": "second@example.com", "password": "hunter22"}
    )
    assert first.json()["is_admin"] is True
    assert second.json()["is_admin"] is False


async def test_registering_the_same_email_twice_is_rejected(anonymous_client: AsyncClient) -> None:
    payload = {"email": "dupe@example.com", "password": "hunter22"}
    first = await anonymous_client.post("/auth/register", json=payload)
    second = await anonymous_client.post("/auth/register", json=payload)
    assert first.status_code == 201
    assert second.status_code == 409


async def test_register_rejects_a_short_password(anonymous_client: AsyncClient) -> None:
    response = await anonymous_client.post(
        "/auth/register", json={"email": "short@example.com", "password": "abc"}
    )
    assert response.status_code == 422


async def test_login_with_wrong_password_is_rejected(anonymous_client: AsyncClient) -> None:
    await anonymous_client.post(
        "/auth/register", json={"email": "user@example.com", "password": "hunter22"}
    )
    response = await anonymous_client.post(
        "/auth/login", json={"email": "user@example.com", "password": "wrong-password"}
    )
    assert response.status_code == 401


async def test_login_with_unknown_email_is_rejected(anonymous_client: AsyncClient) -> None:
    response = await anonymous_client.post(
        "/auth/login", json={"email": "nobody@example.com", "password": "hunter22"}
    )
    assert response.status_code == 401


async def test_protected_endpoint_without_a_token_is_rejected(
    anonymous_client: AsyncClient,
) -> None:
    response = await anonymous_client.get("/exercises")
    assert response.status_code == 401


async def test_protected_endpoint_with_a_garbage_token_is_rejected(
    anonymous_client: AsyncClient,
) -> None:
    anonymous_client.headers["Authorization"] = "Bearer not-a-real-token"
    response = await anonymous_client.get("/exercises")
    assert response.status_code == 401


async def test_me_returns_the_logged_in_user(client: AsyncClient) -> None:
    response = await client.get("/auth/me")
    assert response.status_code == 200
    assert response.json()["email"] == "test@example.com"


async def test_me_without_a_token_is_rejected(anonymous_client: AsyncClient) -> None:
    # `/auth/me` sits under `/auth`, but that prefix is not uniformly public:
    # register and login are the only two endpoints that work unauthenticated.
    # The API description in main.py says so, and this is what keeps that
    # claim true.
    assert (await anonymous_client.get("/auth/me")).status_code == 401


async def test_the_same_token_keeps_working_across_requests_until_logged_out(
    anonymous_client: AsyncClient,
) -> None:
    await anonymous_client.post("/auth/register", json={"email": _EMAIL, "password": _PASSWORD})
    login = await anonymous_client.post(
        "/auth/login", json={"email": _EMAIL, "password": _PASSWORD}
    )
    token = login.json()["access_token"]
    anonymous_client.headers["Authorization"] = f"Bearer {token}"

    for _ in range(3):
        response = await anonymous_client.get("/auth/me")
        assert response.status_code == 200
        assert response.json()["email"] == _EMAIL


async def test_logout_invalidates_the_session_used_to_call_it(client: AsyncClient) -> None:
    assert (await client.get("/auth/me")).status_code == 200

    logout = await client.post("/auth/logout")
    assert logout.status_code == 204

    assert (await client.get("/auth/me")).status_code == 401


async def test_logout_without_a_token_is_rejected(anonymous_client: AsyncClient) -> None:
    assert (await anonymous_client.post("/auth/logout")).status_code == 401


async def test_logout_does_not_affect_other_sessions_for_the_same_account(
    anonymous_client: AsyncClient,
) -> None:
    """Two logins (e.g. two devices) each get their own session -- logging
    one out is not "log out everywhere."
    """
    await anonymous_client.post("/auth/register", json={"email": _EMAIL, "password": _PASSWORD})
    login_a = await anonymous_client.post(
        "/auth/login", json={"email": _EMAIL, "password": _PASSWORD}
    )
    login_b = await anonymous_client.post(
        "/auth/login", json={"email": _EMAIL, "password": _PASSWORD}
    )
    token_a = login_a.json()["access_token"]
    token_b = login_b.json()["access_token"]

    anonymous_client.headers["Authorization"] = f"Bearer {token_a}"
    assert (await anonymous_client.post("/auth/logout")).status_code == 204

    anonymous_client.headers["Authorization"] = f"Bearer {token_a}"
    assert (await anonymous_client.get("/auth/me")).status_code == 401

    anonymous_client.headers["Authorization"] = f"Bearer {token_b}"
    assert (await anonymous_client.get("/auth/me")).status_code == 200
