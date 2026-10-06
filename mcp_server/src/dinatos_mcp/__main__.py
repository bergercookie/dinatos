"""``python -m dinatos_mcp`` / ``dinatos-mcp`` entry point."""

from __future__ import annotations

import anyio
from mcp.server.stdio import stdio_server

from dinatos_mcp.server import build_server


async def _serve() -> None:
    server = build_server()
    async with stdio_server() as (read, write):
        await server.run(read, write, server.create_initialization_options())


def main() -> None:
    anyio.run(_serve)


if __name__ == "__main__":
    main()
