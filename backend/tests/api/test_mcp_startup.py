from httpx2 import AsyncClient


async def test_requests_before_the_mcp_transport_is_running_get_a_503(client: AsyncClient) -> None:
    key = (await client.post("/api-keys", json={"name": "early"})).json()["key"]
    response = await client.post(
        "/mcp",
        headers={
            "Authorization": f"Bearer {key}",
            "Accept": "application/json, text/event-stream",
        },
        json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"},
    )
    assert response.status_code == 503
