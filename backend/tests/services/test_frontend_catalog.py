"""The app's bundled catalog (for its no-server mode) must match what a server seeds."""

import json
from pathlib import Path

from dinatos_backend.services.exercise import catalog_for_local_mode

ASSET = Path(__file__).resolve().parents[3] / "frontend" / "assets" / "exercise_catalog.json"


def test_bundled_catalog_is_up_to_date() -> None:
    bundled = json.loads(ASSET.read_text())
    assert bundled == catalog_for_local_mode(), (
        "frontend/assets/exercise_catalog.json is stale: run "
        "`uv run --project backend python scripts/generate_exercise_catalog.py`"
    )


def test_bundled_catalog_is_not_trivial() -> None:
    bundled = json.loads(ASSET.read_text())
    assert len(bundled) > 500
    assert len({entry["name"] for entry in bundled}) == len(bundled)
