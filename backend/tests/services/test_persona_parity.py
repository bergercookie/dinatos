"""The persona analysis here and the one in the app (`frontend/lib/features/personas/`)
must agree. Both run the cases in `frontend/test/fixtures/persona_parity.json`;
each case's `expected` block was produced by one and checked against the other.

To regenerate after a deliberate change to *both* implementations:
`UPDATE_PERSONA_PARITY=1 uv run pytest tests/services/test_persona_parity.py`,
then run the app's `flutter test test/features/personas`.
"""

import json
import os
from datetime import datetime
from pathlib import Path
from typing import Any

import pytest

from dinatos_backend.services.personas import PERSONAS, analyse_personas

FIXTURE = (
    Path(__file__).resolve().parents[3] / "frontend" / "test" / "fixtures" / "persona_parity.json"
)


def _summary(analysis: dict[str, Any]) -> dict[str, Any]:
    """What both implementations are compared on: the numbers, not row order
    (rows with equal gaps may be listed in either order).
    """
    return {
        "body_features": analysis["body_features"],
        "training_share": analysis["training_share"],
        "training_units": analysis["training_units"],
        "personas": {
            p["id"]: {"body_score": p["body_score"], "training_score": p["training_score"]}
            for p in analysis["personas"]
        },
        "best_body_match": analysis["best_body_match"],
        "best_training_match": analysis["best_training_match"],
        "missing_inputs": analysis["missing_inputs"],
    }


def _run(case: dict[str, Any], now: datetime) -> dict[str, Any]:
    return analyse_personas(
        activities=case["activities"],
        measurements=case["measurements"],
        catalog={e["id"]: e for e in case["catalog"]},
        height_cm=case["height_cm"],
        range_=case["range"],
        now=now,
    )


def _approx(expected: Any) -> Any:
    if isinstance(expected, float):
        return pytest.approx(expected, abs=1e-9)
    if isinstance(expected, dict):
        return {k: _approx(v) for k, v in expected.items()}
    return expected


def test_the_fixture_matches_this_implementation() -> None:
    document = json.loads(FIXTURE.read_text())
    now = datetime.fromisoformat(document["now"].replace("Z", "+00:00"))
    if os.environ.get("UPDATE_PERSONA_PARITY"):
        for case in document["cases"]:
            case["expected"] = _summary(_run(case, now))
        FIXTURE.write_text(json.dumps(document, indent=1) + "\n")
    for case in document["cases"]:
        assert _summary(_run(case, now)) == _approx(case["expected"]), case["name"]


def test_every_persona_trains_to_a_whole() -> None:
    for persona in PERSONAS:
        assert sum(persona.training.values()) == pytest.approx(1.0), persona.id


def test_the_cases_exercise_both_scored_and_unscored_outcomes() -> None:
    document = json.loads(FIXTURE.read_text())
    now = datetime.fromisoformat(document["now"].replace("Z", "+00:00"))
    results = [_run(case, now) for case in document["cases"]]
    assert any(r["best_body_match"] and r["best_training_match"] for r in results)
    assert any(r["best_body_match"] is None and r["best_training_match"] is None for r in results)
    assert any(r["missing_inputs"] for r in results)
