"""Which athlete does this person resemble? The persona analysis behind the
app's Personas page and the MCP server's `get_persona_stats` tool.

The app computes the same thing on the device (`frontend/lib/features/personas/`):
the numbers, the formulas and the personas are the same, and a shared set of
test cases (`frontend/test/fixtures/persona_parity.json`) is run by both
implementations, so they cannot drift apart unnoticed. Change one, change the
other and regenerate the fixture's expected values.

Everything here works on plain dicts shaped like the REST API's responses, so
callers can hand it exactly what they fetched.
"""

import math
import re
from collections.abc import Mapping, Sequence
from dataclasses import asdict, dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Any

# How many body features must be known before a body match is worth showing.
MIN_BODY_FEATURES = 3

# How much logged training (in set-equivalents, see `classify_set`) the
# training match needs before it means anything.
MIN_TRAINING_UNITS = 10.0

# A cardio set is one long effort, so it counts as one set-equivalent per this
# many minutes -- an hour of running must not weigh as much as one bench set.
_MINUTES_PER_SET_EQUIVALENT = 3.0

# Pace assumed to turn a distance with no time into minutes.
_MINUTES_PER_KM = 6.0

_EXPLOSIVE_NAME = re.compile(
    r"\b(jump|clean|snatch|jerk|throw|sprint|plyo|swing|bound|slam|burpee)", re.IGNORECASE
)

RANGE_DAYS: dict[str, int | None] = {"month": 30, "quarter": 90, "year": 365, "all": None}


@dataclass(frozen=True)
class BodyFeature:
    key: str
    label: str
    weight: float  # how much it counts towards a body match


# Height is a weak signal: plenty of great athletes are not the typical height.
BODY_FEATURES: dict[str, BodyFeature] = {
    f.key: f
    for f in (
        BodyFeature("height", "Height (cm)", 0.5),
        BodyFeature("ffmi", "Muscularity (FFMI)", 1),
        BodyFeature("fat_percent", "Body fat (%)", 1),
        BodyFeature("waist_to_height", "Waist-to-height", 1),
        BodyFeature("shoulder_to_waist", "Shoulder-to-waist", 1),
        BodyFeature("thigh_to_height", "Thigh-to-height", 1),
        BodyFeature("arm_to_height", "Arm-to-height", 1),
        BodyFeature("muscle_index", "Muscle mass index", 1),
        BodyFeature("lower_body_muscle", "Lower-body muscle share", 1),
    )
}

TRAINING_FOCUSES: dict[str, str] = {
    "max_strength": "Max strength (heavy weights, 1-5 reps)",
    "muscle_building": "Muscle building (moderate weights, 6-15 reps)",
    "explosive": "Explosive power (jumps, throws, sprints, cleans, snatches, swings)",
    "endurance": "Endurance (running, cycling, long efforts, lots of light reps)",
    "bodyweight_skill": "Bodyweight & skill (pull-ups, dips, holds)",
}


@dataclass(frozen=True)
class BodyTarget:
    ideal: float
    tolerance: float


@dataclass(frozen=True)
class Persona:
    id: str
    name: str
    summary: str
    body: Mapping[str, BodyTarget]
    training: Mapping[str, float]  # fractions of working sets; sums to 1


# Tuned for an adult male build on purpose (the app does not know anyone's sex).
PERSONAS: tuple[Persona, ...] = (
    Persona(
        id="sprinter",
        name="Elite sprinter",
        summary="Powerful, lean and tight at the waist, with big legs for their height.",
        body={
            "height": BodyTarget(180.0, 12.0),
            "ffmi": BodyTarget(22.5, 2.5),
            "fat_percent": BodyTarget(8.0, 4.0),
            "waist_to_height": BodyTarget(0.42, 0.04),
            "shoulder_to_waist": BodyTarget(1.4, 0.15),
            "thigh_to_height": BodyTarget(0.33, 0.04),
            "arm_to_height": BodyTarget(0.19, 0.025),
            "muscle_index": BodyTarget(19.5, 2.5),
            "lower_body_muscle": BodyTarget(0.77, 0.04),
        },
        training={
            "max_strength": 0.25,
            "muscle_building": 0.1,
            "explosive": 0.4,
            "endurance": 0.1,
            "bodyweight_skill": 0.15,
        },
    ),
    Persona(
        id="distance_runner",
        name="Distance runner",
        summary="Light, very lean and narrow, with slim legs and arms built for efficiency.",
        body={
            "height": BodyTarget(175.0, 10.0),
            "ffmi": BodyTarget(19.0, 2.0),
            "fat_percent": BodyTarget(7.0, 3.5),
            "waist_to_height": BodyTarget(0.41, 0.035),
            "shoulder_to_waist": BodyTarget(1.3, 0.15),
            "thigh_to_height": BodyTarget(0.28, 0.035),
            "arm_to_height": BodyTarget(0.16, 0.025),
            "muscle_index": BodyTarget(16.5, 2.0),
            "lower_body_muscle": BodyTarget(0.76, 0.04),
        },
        training={
            "max_strength": 0.05,
            "muscle_building": 0.05,
            "explosive": 0.05,
            "endurance": 0.75,
            "bodyweight_skill": 0.1,
        },
    ),
    Persona(
        id="weightlifter",
        name="Olympic weightlifter",
        summary="Compact and thick through the legs and trunk; strong and explosive.",
        body={
            "height": BodyTarget(170.0, 12.0),
            "ffmi": BodyTarget(24.0, 3.0),
            "fat_percent": BodyTarget(12.0, 5.0),
            "waist_to_height": BodyTarget(0.47, 0.05),
            "shoulder_to_waist": BodyTarget(1.4, 0.15),
            "thigh_to_height": BodyTarget(0.35, 0.04),
            "arm_to_height": BodyTarget(0.2, 0.03),
            "muscle_index": BodyTarget(21.0, 2.5),
            "lower_body_muscle": BodyTarget(0.76, 0.04),
        },
        training={
            "max_strength": 0.5,
            "muscle_building": 0.15,
            "explosive": 0.3,
            "endurance": 0.0,
            "bodyweight_skill": 0.05,
        },
    ),
    Persona(
        id="powerlifter",
        name="Powerlifter",
        summary="Thick and very strong: heavy squat, bench and deadlift, with little else.",
        body={
            "height": BodyTarget(175.0, 12.0),
            "ffmi": BodyTarget(24.0, 3.0),
            "fat_percent": BodyTarget(15.0, 5.0),
            "waist_to_height": BodyTarget(0.5, 0.05),
            "shoulder_to_waist": BodyTarget(1.3, 0.15),
            "thigh_to_height": BodyTarget(0.35, 0.04),
            "arm_to_height": BodyTarget(0.2, 0.03),
            "muscle_index": BodyTarget(21.5, 2.5),
            "lower_body_muscle": BodyTarget(0.74, 0.04),
        },
        training={
            "max_strength": 0.65,
            "muscle_building": 0.25,
            "explosive": 0.0,
            "endurance": 0.0,
            "bodyweight_skill": 0.1,
        },
    ),
    Persona(
        id="bodybuilder",
        name="Bodybuilder",
        summary="Maximum muscle with a very small waist: a pronounced V-taper and big limbs.",
        body={
            "height": BodyTarget(178.0, 15.0),
            "ffmi": BodyTarget(25.5, 2.5),
            "fat_percent": BodyTarget(8.0, 4.0),
            "waist_to_height": BodyTarget(0.42, 0.05),
            "shoulder_to_waist": BodyTarget(1.6, 0.15),
            "thigh_to_height": BodyTarget(0.36, 0.04),
            "arm_to_height": BodyTarget(0.23, 0.03),
            "muscle_index": BodyTarget(22.5, 2.5),
            "lower_body_muscle": BodyTarget(0.7, 0.04),
        },
        training={
            "max_strength": 0.1,
            "muscle_building": 0.8,
            "explosive": 0.0,
            "endurance": 0.05,
            "bodyweight_skill": 0.05,
        },
    ),
    Persona(
        id="gymnast",
        name="Gymnast",
        summary=(
            "Short, very lean and strong for their size, with wide shoulders over a tiny waist."
        ),
        body={
            "height": BodyTarget(166.0, 8.0),
            "ffmi": BodyTarget(22.0, 2.5),
            "fat_percent": BodyTarget(7.0, 3.5),
            "waist_to_height": BodyTarget(0.43, 0.04),
            "shoulder_to_waist": BodyTarget(1.55, 0.15),
            "thigh_to_height": BodyTarget(0.31, 0.04),
            "arm_to_height": BodyTarget(0.2, 0.03),
            "muscle_index": BodyTarget(19.0, 2.5),
            "lower_body_muscle": BodyTarget(0.68, 0.04),
        },
        training={
            "max_strength": 0.15,
            "muscle_building": 0.1,
            "explosive": 0.15,
            "endurance": 0.05,
            "bodyweight_skill": 0.55,
        },
    ),
)


def _positive(value: Any) -> float | None:
    return float(value) if isinstance(value, int | float) and value > 0 else None


def _parse_time(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)


def compute_body_features(
    measurements: Sequence[Mapping[str, Any]], height_cm: float | None = None
) -> dict[str, float]:
    """The most recent logged value of each body feature; a feature that
    cannot be worked out is absent. Each underlying field comes from the
    newest measurement that has it, not from the newest measurement alone.
    """
    newest_first = sorted(measurements, key=lambda m: _parse_time(m["measured_at"]), reverse=True)

    def latest(field: str) -> float | None:
        for m in newest_first:
            value = _positive(m.get(field))
            if value is not None:
                return value
        return None

    def limb(left: str, right: str) -> float | None:
        lv, rv = latest(left), latest(right)
        if lv is not None and rv is not None:
            return (lv + rv) / 2
        return lv if lv is not None else rv

    height = _positive(height_cm)
    weight, fat = latest("weight_kg"), latest("fat_percent")
    waist, shoulder = latest("waist_cm"), latest("shoulder_cm")
    thigh, arm = limb("left_thigh_cm", "right_thigh_cm"), limb("left_bicep_cm", "right_bicep_cm")
    muscle = latest("muscle_mass_kg")
    arm_muscle = limb("left_arm_muscle_kg", "right_arm_muscle_kg")
    leg_muscle = limb("left_leg_muscle_kg", "right_leg_muscle_kg")

    features: dict[str, float] = {}
    if height is not None:
        features["height"] = height
    if height is not None and weight is not None and fat is not None and fat < 100:
        features["ffmi"] = weight * (1 - fat / 100) / math.pow(height / 100, 2)
    if fat is not None:
        features["fat_percent"] = fat
    if height is not None and waist is not None:
        features["waist_to_height"] = waist / height
    if shoulder is not None and waist is not None:
        features["shoulder_to_waist"] = shoulder / waist
    if height is not None and thigh is not None:
        features["thigh_to_height"] = thigh / height
    if height is not None and arm is not None:
        features["arm_to_height"] = arm / height
    if height is not None and muscle is not None:
        features["muscle_index"] = muscle / math.pow(height / 100, 2)
    if arm_muscle is not None and leg_muscle is not None:
        features["lower_body_muscle"] = leg_muscle / (arm_muscle + leg_muscle)
    return features


def missing_body_inputs(
    measurements: Sequence[Mapping[str, Any]], height_cm: float | None = None
) -> list[str]:
    """What to log to unlock more of the body match."""

    def has(field: str) -> bool:
        return any(_positive(m.get(field)) is not None for m in measurements)

    missing: list[str] = []
    if _positive(height_cm) is None:
        missing.append("height (in your profile)")
    if not has("weight_kg"):
        missing.append("weight")
    if not has("fat_percent"):
        missing.append("body fat %")
    if not has("waist_cm"):
        missing.append("waist")
    if not has("shoulder_cm"):
        missing.append("shoulders")
    if not (has("left_thigh_cm") or has("right_thigh_cm")):
        missing.append("thigh")
    if not (has("left_bicep_cm") or has("right_bicep_cm")):
        missing.append("biceps")
    if not has("muscle_mass_kg"):
        missing.append("muscle mass")
    if not (has("left_arm_muscle_kg") or has("right_arm_muscle_kg")) or not (
        has("left_leg_muscle_kg") or has("right_leg_muscle_kg")
    ):
        missing.append("arm and leg muscle (segmental)")
    return missing


def closeness(value: float, target: BodyTarget) -> float:
    """0 (nowhere near) to 1 (spot on): a bell curve one tolerance wide."""
    distance = (value - target.ideal) / target.tolerance
    return math.exp(-0.5 * distance * distance)


def classify_set(
    exercise: Mapping[str, Any] | None, set_: Mapping[str, Any]
) -> tuple[str, float] | None:
    """Which training focus a set counts towards and how many set-equivalents
    it is worth; None for a set with nothing to go on.
    """
    weight = set_.get("weight_kg") or 0
    reps = set_.get("reps") or 0
    distance = set_.get("distance_km") or 0
    seconds = set_.get("duration_seconds") or 0
    explosive = exercise is not None and _EXPLOSIVE_NAME.search(exercise["name"]) is not None

    if weight > 0 and reps > 0:
        if explosive:
            return ("explosive", 1)
        if reps <= 5:
            return ("max_strength", 1)
        if reps <= 15:
            return ("muscle_building", 1)
        return ("endurance", 1)
    if reps > 0:
        if explosive:
            return ("explosive", 1)
        return ("endurance", 1) if reps > 30 else ("bodyweight_skill", 1)
    if seconds > 0 or distance > 0:
        if explosive:
            return ("explosive", 1)
        # A bodyweight hold (plank, hang) is skill and strength, not cardio.
        if distance == 0 and exercise is not None and exercise.get("equipment") == "body_only":
            return ("bodyweight_skill", 1)
        minutes = seconds / 60 if seconds > 0 else distance * _MINUTES_PER_KM
        return ("endurance", max(1.0, minutes / _MINUTES_PER_SET_EQUIVALENT))
    return None


@dataclass(frozen=True)
class TrainingMix:
    share: dict[str, float]
    units: float

    @property
    def is_enough(self) -> bool:
        return self.units >= MIN_TRAINING_UNITS


def compute_training_mix(
    activities: Sequence[Mapping[str, Any]],
    catalog: Mapping[int, Mapping[str, Any]],
    range_: str = "all",
    now: datetime | None = None,
) -> TrainingMix:
    """The person's training as a mix of focuses over the sets they completed
    in the last `range_` (month/quarter/year/all). Warm-ups don't count.
    """
    today: date = (now or datetime.now(UTC)).astimezone(UTC).date()
    days = RANGE_DAYS[range_]
    cutoff = None if days is None else today - timedelta(days=days - 1)

    totals = dict.fromkeys(TRAINING_FOCUSES, 0.0)
    for activity in activities:
        if (
            cutoff is not None
            and _parse_time(activity["started_at"]).astimezone(UTC).date() < cutoff
        ):
            continue
        for entry in activity["exercises"]:
            exercise = catalog.get(entry["exercise_id"])
            for set_ in entry["sets"]:
                if set_.get("set_type") == "warmup" or not set_.get("completed", True):
                    continue
                classified = classify_set(exercise, set_)
                if classified is not None:
                    totals[classified[0]] += classified[1]
    units = sum(totals.values())
    return TrainingMix(
        share={f: (totals[f] / units if units else 0.0) for f in TRAINING_FOCUSES}, units=units
    )


@dataclass(frozen=True)
class _BodyRow:
    feature: str
    you: float
    ideal: float
    closeness: float


@dataclass(frozen=True)
class _TrainingRow:
    focus: str
    you: float
    ideal: float

    @property
    def gap(self) -> float:
        """Positive when the persona does more of this than the person."""
        return self.ideal - self.you


def _score_persona(
    persona: Persona, body: Mapping[str, float], training: TrainingMix
) -> dict[str, Any]:
    body_rows = sorted(
        (
            _BodyRow(key, body[key], target.ideal, closeness(body[key], target))
            for key, target in persona.body.items()
            if key in body
        ),
        key=lambda row: row.closeness,
        reverse=True,
    )
    body_score: float | None = None
    if len(body_rows) >= MIN_BODY_FEATURES:
        weighted = sum(BODY_FEATURES[r.feature].weight * r.closeness for r in body_rows)
        weights = sum(BODY_FEATURES[r.feature].weight for r in body_rows)
        body_score = 100 * weighted / weights

    training_rows = sorted(
        (
            _TrainingRow(focus, training.share.get(focus, 0.0), persona.training.get(focus, 0.0))
            for focus in TRAINING_FOCUSES
        ),
        key=lambda row: abs(row.gap),
        reverse=True,
    )
    training_score: float | None = None
    if training.is_enough:
        # One minus the total variation distance: the share of the person's
        # training that already overlaps the persona's.
        distance = sum(abs(r.gap) for r in training_rows) / 2
        training_score = 100 * (1 - distance)

    return {
        "id": persona.id,
        "name": persona.name,
        "summary": persona.summary,
        "body_score": body_score,
        "training_score": training_score,
        "body_rows": [asdict(r) for r in body_rows],
        "training_rows": [{**asdict(r), "gap": r.gap} for r in training_rows],
    }


def analyse_personas(
    *,
    activities: Sequence[Mapping[str, Any]],
    measurements: Sequence[Mapping[str, Any]],
    catalog: Mapping[int, Mapping[str, Any]],
    height_cm: float | None = None,
    range_: str = "quarter",
    now: datetime | None = None,
) -> dict[str, Any]:
    """The whole Personas page as JSON-ready data."""
    body = compute_body_features(measurements, height_cm)
    training = compute_training_mix(activities, catalog, range_, now)
    matches = [_score_persona(p, body, training) for p in PERSONAS]

    def best(key: str) -> str | None:
        scored = [m for m in matches if m[key] is not None]
        return max(scored, key=lambda m: m[key])["id"] if scored else None

    return {
        "range": range_,
        "body_features": body,
        "missing_inputs": missing_body_inputs(measurements, height_cm),
        "training_units": training.units,
        "training_share": training.share,
        "training_enough": training.is_enough,
        "personas": matches,
        "best_body_match": best("body_score"),
        "best_training_match": best("training_score"),
    }


__all__ = ["PERSONAS", "RANGE_DAYS", "analyse_personas"]
