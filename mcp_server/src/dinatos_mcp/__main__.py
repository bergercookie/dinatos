"""``python -m dinatos_mcp`` / ``dinatos-mcp`` entry point."""

from __future__ import annotations

from dinatos_mcp.server import mcp


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
