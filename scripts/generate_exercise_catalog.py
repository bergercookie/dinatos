"""Writes frontend/assets/exercise_catalog.json: the built-in exercise catalog
(name, what it tracks, equipment, muscles -- no tutorial text) the app ships
for its no-server "local mode", generated from the very data the backend
seeds a new server with so the two always agree on names.

    uv run --project backend python scripts/generate_exercise_catalog.py

`backend/tests/services/test_frontend_catalog.py` fails when the committed
file is out of date, so re-run this after the backend's catalog changes.
"""

import json
from pathlib import Path

from dinatos_backend.services.exercise import catalog_for_local_mode

OUTPUT = Path(__file__).resolve().parent.parent / "frontend" / "assets" / "exercise_catalog.json"


def main() -> None:
    OUTPUT.write_text(json.dumps(catalog_for_local_mode(), separators=(",", ":")) + "\n")
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()
