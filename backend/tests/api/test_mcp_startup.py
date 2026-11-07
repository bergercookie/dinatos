import asyncio

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
    monkeypatch.setattr(
        "dinatos_backend.services.instance_settings.get_settings",
        lambda: Settings(mcp_enabled=False),
    )
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


_MCP_HEADERS = {"Accept": "application/json, text/event-stream"}
_LIST_TOOLS = {"jsonrpc": "2.0", "id": 1, "method": "tools/list"}


async def _running_gateway() -> tuple[asyncio.Task[None], asyncio.Event]:
    """Runs the gateway in a task of its own (its transport's task group must be
    entered and left by the same task); set the returned event to stop it.
    """
    started, stop = asyncio.Event(), asyncio.Event()

    async def run() -> None:
        async with mcp_gateway.running():
            started.set()
            await stop.wait()

    task = asyncio.create_task(run())
    await started.wait()
    return task, stop


async def test_the_admin_switch_turns_mcp_off_and_on_while_it_runs(client: AsyncClient) -> None:
    """Without the variable, the transport starts, and the admin's switch decides
    at request time: no restart is needed in either direction.
    """
    key = (await client.post("/api-keys", json={"name": "switch"})).json()["key"]
    headers = {**_MCP_HEADERS, "Authorization": f"Bearer {key}"}
    task, stop = await _running_gateway()
    try:
        assert mcp_gateway._manager is not None
        assert (await client.post("/mcp", headers=headers, json=_LIST_TOOLS)).status_code == 200

        # `client` is the first account, so it is the admin.
        await client.patch("/admin/settings", json={"mcp_enabled": False})
        off = await client.post("/mcp", headers=headers, json=_LIST_TOOLS)
        assert off.status_code == 404
        assert off.json() == {"detail": "the MCP server is disabled"}

        await client.patch("/admin/settings", json={"mcp_enabled": True})
        assert (await client.post("/mcp", headers=headers, json=_LIST_TOOLS)).status_code == 200
    finally:
        stop.set()
        await task
