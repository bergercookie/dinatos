"""``python -m dinatos_backend`` / ``dinatos-backend`` entry point."""

from __future__ import annotations

import os

import uvicorn


def main() -> None:
    uvicorn.run(
        "dinatos_backend.main:app",
        host=os.environ.get("DINATOS_HOST", "127.0.0.1"),
        port=int(os.environ.get("DINATOS_PORT", "8000")),
        reload=True,
    )


if __name__ == "__main__":
    main()
