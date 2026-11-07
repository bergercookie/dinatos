import pytest
from httpx2 import AsyncClient

from dinatos_backend.api.mcp import mcp_gateway
from dinatos_backend.config import Settings


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


async def test_a_disabled_mcp_server_answers_404_and_does_not_start(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr("dinatos_backend.api.mcp.get_settings", lambda: Settings(mcp_enabled=False))
    key = (await client.post("/api-keys", json={"name": "off"})).json()["key"]
    async with mcp_gateway.running():
        assert mcp_gateway._manager is None
        response = await client.post(
            "/mcp",
            headers={
                "Authorization": f"Bearer {key}",
                "Accept": "application/json, text/event-stream",
            },
            json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"},
        )
    assert response.status_code == 404
    assert response.json() == {"detail": "the MCP server is disabled"}
