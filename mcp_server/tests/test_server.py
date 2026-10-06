import mcp.types as types
import pytest

from dinatos_mcp.config import get_settings
from dinatos_mcp.server import DinatosAuthError, DinatosConfigError, RemoteTools, build_server

pytestmark = pytest.mark.usefixtures("configured")

EXPECTED_TOOLS = {
    "list_exercises",
    "create_exercise",
    "list_routines",
    "create_routine",
    "list_activities",
    "log_activity",
    "get_persona_stats",
}


async def test_lists_whatever_tools_the_server_offers(remote: RemoteTools) -> None:
    tools = await remote.list_tools()
    assert {t.name for t in tools} == EXPECTED_TOOLS
    assert all(t.description for t in tools)


async def test_calls_a_tool_on_the_server(remote: RemoteTools) -> None:
    created = await remote.call_tool("create_exercise", {"name": "Deadlift (Barbell)"})
    assert not created.isError
    assert "Deadlift (Barbell)" in created.content[0].text  # type: ignore[union-attr]
    listed = await remote.call_tool("list_exercises", {"search": "dead"})
    assert "Deadlift (Barbell)" in listed.content[0].text  # type: ignore[union-attr]


async def test_persona_stats_are_reachable_through_the_proxy(remote: RemoteTools) -> None:
    result = await remote.call_tool("get_persona_stats", {"range": "month"})
    assert not result.isError
    assert '"powerlifter"' in result.content[0].text  # type: ignore[union-attr]


async def test_a_server_error_comes_back_as_a_tool_error(remote: RemoteTools) -> None:
    result = await remote.call_tool(
        "log_activity",
        {
            "title": "Ghost",
            "started_at": "2026-10-01T10:00:00Z",
            "exercises": [],
            "routine_id": 999999,
        },
    )
    assert result.isError
    assert "routine not found" in result.content[0].text  # type: ignore[union-attr]


async def test_no_api_key_is_a_clear_error(
    remote: RemoteTools, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("DINATOS_MCP_API_KEY")
    get_settings.cache_clear()
    with pytest.raises(DinatosConfigError, match="API key"):
        await remote.list_tools()


async def test_a_wrong_api_key_is_refused(
    remote: RemoteTools, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("DINATOS_MCP_API_KEY", "dnk_wrong")
    get_settings.cache_clear()
    with pytest.raises(DinatosAuthError, match="refused the API key"):
        await remote.list_tools()


async def test_the_stdio_server_forwards_both_requests(remote: RemoteTools) -> None:
    server = build_server(remote)
    listed = await server.request_handlers[types.ListToolsRequest](
        types.ListToolsRequest(method="tools/list")
    )
    assert {t.name for t in listed.root.tools} == EXPECTED_TOOLS  # type: ignore[union-attr]
    called = await server.request_handlers[types.CallToolRequest](
        types.CallToolRequest(
            method="tools/call",
            params=types.CallToolRequestParams(name="list_exercises", arguments={}),
        )
    )
    assert called.root.isError is False  # type: ignore[union-attr]


async def test_other_failures_are_not_mistaken_for_a_refused_key() -> None:
    import httpx

    def broken(
        headers: dict[str, str] | None = None,
        timeout: httpx.Timeout | None = None,
        auth: httpx.Auth | None = None,
    ) -> httpx.AsyncClient:
        transport = httpx.MockTransport(lambda _request: httpx.Response(500))
        return httpx.AsyncClient(
            transport=transport, base_url="http://test", headers=headers, timeout=timeout, auth=auth
        )

    with pytest.raises(BaseExceptionGroup) as raised:
        await RemoteTools(http_client_factory=broken).list_tools()
    assert not raised.group_contains(DinatosAuthError)
