"""Best-effort metadata for the custom exercises a Hevy import has to create.

Hevy's CSV carries nothing but an exercise *title* -- no equipment, no
muscles -- so when `hevy_exercise_match` finds no catalog exercise for a
title and the importer creates a custom one, that exercise would otherwise
be born with no equipment and no muscles, and the "which muscles got the
most volume" views would silently ignore it. This module guesses both,
deterministically (no network, no model) and in a way that can be explained
from the title alone:

* **Equipment** comes from the parenthesised suffix Hevy appends
  ("Row (Dumbbell)" -> dumbbell), via `_SUFFIX_EQUIPMENT`; failing that,
  from equipment words in the name itself ("Dumbbell Row"), via
  `_KEYWORD_EQUIPMENT`. An unrecognised suffix ("(Banana)") is ignored.
* **Muscles** come from the most similar *seeded catalog* exercises: names
  are compared as word sets after stripping equipment/filler words (Dice
  coefficient, so "Row (Dumbbell)" ~ "Bent Over Two-Dumbbell Row"), and the
  muscles of up to `_TOP_K` neighbours scoring at least `_MIN_SIMILARITY`
  (and close to the best one) are voted on, weighted by similarity. If no
  neighbour is good enough, a small movement-keyword table (`_MUSCLE_RULES`:
  row -> back, curl -> biceps, ...) is tried. If that finds nothing either,
  the muscles stay empty -- an empty answer is better than a wild one.

Only the shipped catalog is used as a neighbour source, never a person's own
exercises (or earlier guesses): that keeps the answer independent of what
else happens to exist or be imported, so re-running gives the same result.
Everything here is a *guess* -- the importer reports it as such so the UI
can ask the person to review it.
"""

import re
from collections import defaultdict
from dataclasses import dataclass, field

from dinatos_backend.models.exercise import Equipment, Exercise, MuscleGroup
from dinatos_backend.services.hevy_exercise_match import words_of

# Lowercased contents of Hevy's "(...)" suffix -> our Equipment.
_SUFFIX_EQUIPMENT: dict[str, Equipment] = {
    "barbell": Equipment.barbell,
    "dumbbell": Equipment.dumbbell,
    "dumbbells": Equipment.dumbbell,
    "cable": Equipment.cable,
    "machine": Equipment.machine,
    "smith machine": Equipment.machine,
    "smith": Equipment.machine,
    "machine plates": Equipment.machine,
    "plate loaded": Equipment.machine,
    "pec deck": Equipment.machine,
    "assisted": Equipment.machine,
    "kettlebell": Equipment.kettlebells,
    "kettlebells": Equipment.kettlebells,
    "bodyweight": Equipment.body_only,
    "body weight": Equipment.body_only,
    "weighted": Equipment.body_only,
    "none": Equipment.body_only,
    "band": Equipment.bands,
    "bands": Equipment.bands,
    "resistance band": Equipment.bands,
    "ez bar": Equipment.e_z_curl_bar,
    "ez-bar": Equipment.e_z_curl_bar,
    "ez curl bar": Equipment.e_z_curl_bar,
    "medicine ball": Equipment.medicine_ball,
    "swiss ball": Equipment.exercise_ball,
    "stability ball": Equipment.exercise_ball,
    "exercise ball": Equipment.exercise_ball,
    "foam roller": Equipment.foam_roll,
    "foam roll": Equipment.foam_roll,
    "suspension": Equipment.other,
    "trx": Equipment.other,
    "plate": Equipment.other,
    "other": Equipment.other,
}

# Equipment words in the (suffix-less) name, searched on word boundaries.
# Order matters: more specific phrases first ("ez bar" before "bar").
_KEYWORD_EQUIPMENT: tuple[tuple[str, Equipment], ...] = (
    (r"ez[- ]?(?:curl[- ]?)?bar", Equipment.e_z_curl_bar),
    (r"smith(?: machine)?", Equipment.machine),
    (r"medicine ball", Equipment.medicine_ball),
    (r"(?:swiss|stability|exercise) ball", Equipment.exercise_ball),
    (r"foam roll(?:er)?", Equipment.foam_roll),
    (r"dumb?bells?", Equipment.dumbbell),
    (r"barbell", Equipment.barbell),
    (r"kettlebells?", Equipment.kettlebells),
    (r"cables?", Equipment.cable),
    (r"machine", Equipment.machine),
    (r"(?:resistance )?bands?", Equipment.bands),
    (
        r"(?:body ?weight|push[- ]?ups?|pull[- ]?ups?|chin[- ]?ups?|sit[- ]?ups?|planks?)",
        Equipment.body_only,
    ),
)

_SUFFIX_RE = re.compile(r"\s*\(([^()]*)\)\s*$")

# Words dropped before comparing names: equipment (already captured
# separately, and spelled differently on each side), and grip/filler words
# that don't change which muscles work.
_EQUIPMENT_WORDS = frozenset(
    {
        "dumbbell", "dumbell", "barbell", "cable", "machine", "smith", "kettlebell", "band",
        "ez", "bar", "plate", "lever", "leverage", "weighted", "assisted", "resistance",
    }
)  # fmt: skip
_FILLER_WORDS = frozenset(
    {"with", "on", "the", "of", "and", "to", "a", "an", "grip", "medium", "handle", "attachment"}
)

# Below this Dice similarity a catalog exercise is not considered "the same
# movement" at all. 0.6 means e.g. two of three words shared ("lateral
# raise" vs "side lateral raise" = 0.8; "row" vs "upright row" = 0.67) while
# one shared word in a three-word name (0.4) is not enough.
_MIN_SIMILARITY = 0.6
# Neighbours further than this below the best one are not allowed to vote.
_SIMILARITY_BAND = 0.15
_TOP_K = 3
# A muscle must be trained by at least this share of the voting weight.
_MIN_VOTE_SHARE = 0.5


@dataclass(frozen=True)
class MuscleRule:
    """Matches when every `all_of` word and at least one `any_of` word (if
    given) is among the name's words; first matching rule in `_MUSCLE_RULES`
    wins, so specific rules come before general ones.
    """

    primary: tuple[MuscleGroup, ...]
    secondary: tuple[MuscleGroup, ...] = ()
    any_of: frozenset[str] = frozenset()
    all_of: frozenset[str] = frozenset()

    def matches(self, name_words: frozenset[str]) -> bool:
        return self.all_of <= name_words and (not self.any_of or bool(self.any_of & name_words))


def _rule(
    any_of: str,
    primary: tuple[MuscleGroup, ...],
    secondary: tuple[MuscleGroup, ...] = (),
    *,
    all_of: str = "",
) -> MuscleRule:
    return MuscleRule(
        primary=primary,
        secondary=secondary,
        any_of=frozenset(any_of.split()),
        all_of=frozenset(all_of.split()),
    )


_M = MuscleGroup
# Words are matched after `words_of` folding: lowercased, a trailing "s"
# dropped ("curls" -> "curl", "biceps" -> "bicep"), "pull up" -> "pullup".
_MUSCLE_RULES: tuple[MuscleRule, ...] = (
    _rule("curl", (_M.hamstrings,), (_M.calves,), all_of="leg"),
    _rule("curl", (_M.hamstrings,), all_of="hamstring"),
    _rule("wrist", (_M.forearms,)),
    _rule("forearm", (_M.forearms,)),
    _rule("calf", (_M.calves,)),
    _rule("press", (_M.quadriceps,), (_M.glutes, _M.hamstrings), all_of="leg"),
    _rule("extension", (_M.quadriceps,), all_of="leg"),
    _rule("abduction abductor", (_M.abductors,), (_M.glutes,)),
    _rule("adduction adductor", (_M.adductors,)),
    _rule("tricep skullcrusher pushdown", (_M.triceps,), (_M.shoulders,)),
    _rule("bicep curl", (_M.biceps,), (_M.forearms,)),
    _rule("shrug", (_M.traps,), (_M.shoulders,)),
    _rule("neck", (_M.neck,)),
    _rule("hyperextension extension", (_M.lower_back,), (_M.glutes, _M.hamstrings), all_of="back"),
    _rule("pulldown pullup chinup lat", (_M.lats,), (_M.biceps, _M.middle_back)),
    _rule("pullover", (_M.lats,), (_M.chest, _M.triceps)),
    _rule("row", (_M.middle_back, _M.lats), (_M.biceps, _M.shoulders)),
    _rule("lateral delt arnold", (_M.shoulders,), (_M.triceps,)),
    _rule("raise", (_M.shoulders,), all_of="front"),
    _rule("pull", (_M.shoulders,), (_M.traps, _M.middle_back), all_of="face"),
    _rule("fly flye", (_M.shoulders,), (_M.middle_back, _M.traps), all_of="reverse"),
    _rule("fly flye", (_M.shoulders,), (_M.middle_back, _M.traps), all_of="rear"),
    _rule("fly flye pec crossover", (_M.chest,), (_M.shoulders, _M.triceps)),
    _rule("bench chest pushup dip incline decline", (_M.chest,), (_M.shoulders, _M.triceps)),
    _rule("press overhead military", (_M.shoulders,), (_M.triceps,)),
    _rule("squat lunge hack", (_M.quadriceps,), (_M.glutes, _M.hamstrings)),
    _rule("stepup", (_M.quadriceps,), (_M.glutes,)),
    _rule("deadlift", (_M.hamstrings, _M.glutes), (_M.lower_back,)),
    _rule("morning", (_M.hamstrings,), (_M.lower_back, _M.glutes), all_of="good"),
    _rule("thrust bridge glute", (_M.glutes,), (_M.hamstrings,)),
    _rule("crunch situp plank ab abs twist", (_M.abdominals,)),
    _rule("raise", (_M.abdominals,), all_of="leg"),
)


@dataclass
class InferredMetadata:
    """What `ExerciseInferrer.infer` could say about one title. Empty/`None`
    means "no confident answer", never "this exercise has none".
    """

    equipment: Equipment | None = None
    primary_muscles: list[MuscleGroup] = field(default_factory=list)
    secondary_muscles: list[MuscleGroup] = field(default_factory=list)

    @property
    def has_muscles(self) -> bool:
        return bool(self.primary_muscles or self.secondary_muscles)


def split_equipment_suffix(name: str) -> tuple[str, str | None]:
    """ "Row (Dumbbell)" -> ("Row", "dumbbell"); no suffix -> (name, None)."""
    found = _SUFFIX_RE.search(name)
    if found is None:
        return name.strip(), None
    return name[: found.start()].strip(), found.group(1).strip().lower()


def infer_equipment(name: str) -> Equipment | None:
    base, suffix = split_equipment_suffix(name)
    if suffix is not None and suffix in _SUFFIX_EQUIPMENT:
        return _SUFFIX_EQUIPMENT[suffix]
    for pattern, equipment in _KEYWORD_EQUIPMENT:
        if re.search(rf"\b{pattern}\b", base.lower()):
            return equipment
    return None


def _movement_words(name: str) -> frozenset[str]:
    """The words that identify the *movement*: suffix, equipment and filler
    removed ("Bent Over Row (Dumbbell)" -> {bent, over, row})."""
    base, _ = split_equipment_suffix(name)
    return frozenset(words_of(base) - _EQUIPMENT_WORDS - _FILLER_WORDS)


def _dice(a: frozenset[str], b: frozenset[str]) -> float:
    if not a or not b:
        return 0.0
    return 2 * len(a & b) / (len(a) + len(b))


class ExerciseInferrer:
    """Built once per import from the seeded (non-custom) exercises, whose
    `muscles` must already be loaded (async SQLAlchemy can't lazy-load).
    """

    def __init__(self, catalog: list[Exercise]) -> None:
        self._neighbours: list[tuple[str, frozenset[str], Exercise]] = []
        for exercise in catalog:
            movement = _movement_words(exercise.name)
            if movement and exercise.muscles:
                self._neighbours.append((exercise.name, movement, exercise))

    def similar(self, name: str) -> list[tuple[float, Exercise]]:
        """Up to `_TOP_K` catalog exercises similar enough to vote, best
        first; ties broken by catalog name so the order is deterministic."""
        movement = _movement_words(name)
        scored = [
            (_dice(movement, words), catalog_name, exercise)
            for catalog_name, words, exercise in self._neighbours
        ]
        scored = [entry for entry in scored if entry[0] >= _MIN_SIMILARITY]
        scored.sort(key=lambda entry: (-entry[0], entry[1]))
        if not scored:
            return []
        best = scored[0][0]
        return [
            (score, exercise)
            for score, _, exercise in scored[:_TOP_K]
            if score >= best - _SIMILARITY_BAND
        ]

    def infer(self, name: str) -> InferredMetadata:
        result = InferredMetadata(equipment=infer_equipment(name))
        neighbours = self.similar(name)
        if neighbours:
            result.primary_muscles, result.secondary_muscles = _vote(neighbours)
        if not result.has_muscles:
            words = _movement_words(name)
            for rule in _MUSCLE_RULES:
                if rule.matches(words):
                    result.primary_muscles = list(rule.primary)
                    result.secondary_muscles = list(rule.secondary)
                    break
        return result


def _vote(neighbours: list[tuple[float, Exercise]]) -> tuple[list[MuscleGroup], list[MuscleGroup]]:
    primary_weight: dict[MuscleGroup, float] = defaultdict(float)
    secondary_weight: dict[MuscleGroup, float] = defaultdict(float)
    total = 0.0
    for score, exercise in neighbours:
        total += score
        for muscle in exercise.primary_muscles:
            primary_weight[muscle] += score
        for muscle in exercise.secondary_muscles:
            secondary_weight[muscle] += score

    primary: list[MuscleGroup] = []
    secondary: list[MuscleGroup] = []
    for muscle in sorted(set(primary_weight) | set(secondary_weight)):
        p, s = primary_weight[muscle], secondary_weight[muscle]
        if (p + s) / total < _MIN_VOTE_SHARE:
            continue
        (primary if p >= s else secondary).append(muscle)
    return primary, secondary
