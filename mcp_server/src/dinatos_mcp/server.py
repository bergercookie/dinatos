"""A stdio MCP server that forwards to a Dinatos server's own MCP endpoint.

The Dinatos server hosts the real MCP server at `https://<your dinatos>/mcp`;
a client that can speak to a URL (Claude, ...) should just use that, with an
API key, and needs nothing installed. This package exists for clients that can
only launch a local program: it has no tools of its own, it lists and calls
whatever the server offers, so the two can never disagree.
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

import httpx
import mcp.types as types
from mcp.client.session import ClientSession
from mcp.client.streamable_http import streamablehttp_client
from mcp.server.lowlevel import Server
from mcp.shared._httpx_utils import McpHttpClientFactory, create_mcp_http_client

from dinatos_mcp.config import get_settings


class DinatosConfigError(RuntimeError):
    """No API key configured."""


class DinatosAuthError(RuntimeError):
    """The Dinatos server refused the API key."""


class RemoteTools:
    """Opens a short-lived session to the server's `/mcp` per request: the
    endpoint is stateless, so there is nothing to keep alive between calls.
    """

    def __init__(self, http_client_factory: McpHttpClientFactory = create_mcp_http_client) -> None:
        self._factory = http_client_factory

    @asynccontextmanager
    async def _session(self) -> AsyncIterator[ClientSession]:
        settings = get_settings()
        if not settings.api_key:
            raise DinatosConfigError(
                "no Dinatos API key configured -- create one in the app (Settings > API keys) "
                "and set DINATOS_MCP_API_KEY"
            )
        try:
            async with (
                streamablehttp_client(
                    settings.mcp_url,
                    headers={"Authorization": f"Bearer {settings.api_key}"},
                    httpx_client_factory=self._factory,
                ) as (read, write, _),
                ClientSession(read, write) as session,
            ):
                await session.initialize()
                yield session
        except BaseExceptionGroup as group:
            refused, rest = group.split(
                lambda e: isinstance(e, httpx.HTTPStatusError) and e.response.status_code == 401
            )
            if refused is not None and rest is None:
                raise DinatosAuthError(
                    "the Dinatos server refused the API key -- check DINATOS_MCP_API_KEY "
                    "(it may have been deleted in Settings > API keys)"
                ) from None
            raise

    async def list_tools(self) -> list[types.Tool]:
        async with self._session() as session:
            return (await session.list_tools()).tools

    async def call_tool(self, name: str, arguments: dict[str, Any] | None) -> types.CallToolResult:
        """The server's own result, errors and structured content included."""
        async with self._session() as session:
            return await session.call_tool(name, arguments or {})


def build_server(remote: RemoteTools | None = None) -> Server:
    remote = remote or RemoteTools()
    server = Server(
        "dinatos",
        instructions=(
            "Manage a Dinatos workout tracker: exercises, routines, activities and persona "
            "statistics. These tools are provided by the Dinatos server itself."
        ),
    )

    @server.list_tools()  # type: ignore[no-untyped-call,untyped-decorator]
    async def _list_tools() -> list[types.Tool]:
        return await remote.list_tools()

    # The server validates arguments against its own schemas; there is no
    # point validating against a copy of them here too.
    @server.call_tool(validate_input=False)  # type: ignore[untyped-decorator]
    async def _call_tool(name: str, arguments: dict[str, Any]) -> types.CallToolResult:
        return await remote.call_tool(name, arguments)

    return server
