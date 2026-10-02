/// Mirrors `dinatos_backend.models.exercise.MuscleGroup` -- a fixed, closed
/// vocabulary (not free text) for what an exercise trains, so a person's
/// logged sets can eventually be reasoned about by muscle, not just shown
/// as a label.
enum MuscleGroup {
  abdominals,
  abductors,
  adductors,
  biceps,
  calves,
  chest,
  forearms,
  glutes,
  hamstrings,
  lats,
  lowerBack,
  middleBack,
  neck,
  quadriceps,
  shoulders,
  traps,
  triceps;

  /// The handful of members whose backend wire value (snake_case, matching
  /// the vendored dataset -- see `MuscleGroup`'s own docstring) differs from
  /// this enum's lowerCamelCase Dart name; every other member's wire value
  /// is just its [name].
  static const _wireNames = <MuscleGroup, String>{
    MuscleGroup.lowerBack: 'lower_back',
    MuscleGroup.middleBack: 'middle_back',
  };

  static MuscleGroup fromJson(String value) {
    for (final entry in _wireNames.entries) {
      if (entry.value == value) return entry.key;
    }
    return MuscleGroup.values.byName(value);
  }

  String toJson() => _wireNames[this] ?? name;

  /// A human-readable label for chips/dropdowns, e.g. "Lower back".
  String get label {
    final wire = toJson().replaceAll('_', ' ');
    return wire[0].toUpperCase() + wire.substring(1);
  }
}
