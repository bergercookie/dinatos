"""Exercises added to the shipped catalog after the vendored dataset.

`data/free_exercise_db.json` has almost nothing for tendinopathy rehab and
load management (isometric holds, slow eccentrics, heavy-slow-resistance
work, calf/hamstring/hip strengthening), so these supplement it. They are
seeded alongside the dataset into a brand new instance (see
`services.exercise.bootstrap_default_exercises`) and applied once to an
existing instance by the `add_rehab_exercises` migration, which also
reconciles any same-named exercise a person already created.

Muscle vocabulary note: `MuscleGroup` has no shin/tibialis, so tibialis work
is tagged `calves` (the closest lower-leg group).

Adding more later: put them in a *new* list and a *new* migration rather than
editing this one -- a migration only ever runs once per instance.
"""

from collections.abc import Sequence
from dataclasses import dataclass

from dinatos_backend.models.exercise import Equipment, MuscleGroup

_E = Equipment
_M = MuscleGroup


@dataclass(frozen=True)
class CatalogAddition:
    name: str
    equipment: Equipment
    primary: tuple[MuscleGroup, ...]
    secondary: tuple[MuscleGroup, ...] = ()
    tracks_weight: bool = False
    tracks_reps: bool = False
    tracks_distance: bool = False
    tracks_duration: bool = False

    @property
    def specs(self) -> tuple[bool, bool, bool, bool]:
        return (
            self.tracks_weight,
            self.tracks_reps,
            self.tracks_distance,
            self.tracks_duration,
        )


def _reps(
    name: str,
    equipment: Equipment,
    primary: Sequence[MuscleGroup],
    secondary: Sequence[MuscleGroup] = (),
    *,
    weight: bool = False,
) -> CatalogAddition:
    return CatalogAddition(
        name, equipment, tuple(primary), tuple(secondary), tracks_weight=weight, tracks_reps=True
    )


def _hold(
    name: str,
    equipment: Equipment,
    primary: Sequence[MuscleGroup],
    secondary: Sequence[MuscleGroup] = (),
    *,
    weight: bool = False,
) -> CatalogAddition:
    return CatalogAddition(
        name,
        equipment,
        tuple(primary),
        tuple(secondary),
        tracks_weight=weight,
        tracks_duration=True,
    )


ADDITIONS: tuple[CatalogAddition, ...] = (
    # Patellar / quadriceps tendon
    _hold("Spanish Squat (Isometric)", _E.bands, [_M.quadriceps], [_M.glutes, _M.hamstrings]),
    _hold("Wall Sit", _E.body_only, [_M.quadriceps], [_M.glutes, _M.calves]),
    _hold("Isometric Leg Extension", _E.machine, [_M.quadriceps], weight=True),
    _hold("Isometric Split Squat Hold", _E.body_only, [_M.quadriceps], [_M.glutes], weight=True),
    _reps("Decline Single-Leg Squat", _E.body_only, [_M.quadriceps], [_M.glutes, _M.hamstrings]),
    _reps("Eccentric Step-Down", _E.body_only, [_M.quadriceps], [_M.glutes]),
    _reps("Terminal Knee Extension (Band)", _E.bands, [_M.quadriceps]),
    _reps("Eccentric Single-Leg Extension", _E.machine, [_M.quadriceps], weight=True),
    _reps(
        "Heavy Slow Resistance Leg Press",
        _E.machine,
        [_M.quadriceps],
        [_M.glutes, _M.hamstrings],
        weight=True,
    ),
    _reps("Reverse Nordic Curl", _E.body_only, [_M.quadriceps]),
    # Achilles / calf / plantar fascia / ankle
    _reps("Eccentric Heel Drop (Straight Knee)", _E.body_only, [_M.calves], weight=True),
    _reps("Eccentric Heel Drop (Bent Knee)", _E.body_only, [_M.calves], weight=True),
    _reps("Single-Leg Standing Calf Raise", _E.body_only, [_M.calves], weight=True),
    _hold("Isometric Calf Raise Hold", _E.body_only, [_M.calves], weight=True),
    _reps("Plantar Fascia Calf Raise (Rolled Towel)", _E.body_only, [_M.calves], weight=True),
    _reps("Tibialis Raise (Wall)", _E.body_only, [_M.calves], weight=True),
    CatalogAddition(
        "Short-Foot Exercise",
        _E.body_only,
        (_M.calves,),
        tracks_reps=True,
        tracks_duration=True,
    ),
    _reps("Ankle Eversion (Band)", _E.bands, [_M.calves]),
    _reps("Ankle Inversion (Band)", _E.bands, [_M.calves]),
    _hold("Single-Leg Balance", _E.body_only, [_M.calves], [_M.glutes]),
    # Hamstring / proximal hamstring tendon
    _reps("Nordic Hamstring Curl", _E.body_only, [_M.hamstrings], [_M.glutes]),
    _reps("Hamstring Slider Curl", _E.body_only, [_M.hamstrings], [_M.glutes]),
    _hold("Isometric Heel-Dig Hold", _E.body_only, [_M.hamstrings], [_M.glutes]),
    _reps(
        "Single-Leg Romanian Deadlift",
        _E.dumbbell,
        [_M.hamstrings],
        [_M.glutes, _M.lower_back],
        weight=True,
    ),
    # Gluteal tendon / hip / adductors
    _hold("Isometric Glute Bridge Hold", _E.body_only, [_M.glutes], [_M.hamstrings], weight=True),
    _reps("Clamshell (Band)", _E.bands, [_M.abductors], [_M.glutes]),
    _reps("Side-Lying Hip Abduction", _E.body_only, [_M.abductors], [_M.glutes]),
    _hold("Isometric Wall Hip Abduction", _E.body_only, [_M.abductors], [_M.glutes]),
    _reps("Lateral Band Walk", _E.bands, [_M.abductors], [_M.glutes]),
    _hold("Copenhagen Plank", _E.body_only, [_M.adductors], [_M.abdominals]),
    _hold("Isometric Adductor Squeeze (Ball)", _E.exercise_ball, [_M.adductors]),
    # Low-impact conditioning that keeps tendons moving
    CatalogAddition(
        "Stationary Bike (Easy Spin)",
        _E.machine,
        (_M.quadriceps,),
        (_M.hamstrings, _M.glutes, _M.calves),
        tracks_distance=True,
        tracks_duration=True,
    ),
)
