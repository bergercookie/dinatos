/// Mirrors `dinatos_backend.models.exercise.Equipment` -- same
/// closed-vocabulary reasoning as [MuscleGroup], for what an exercise is
/// performed with.
enum Equipment {
  bands,
  barbell,
  bodyOnly,
  cable,
  dumbbell,
  eZCurlBar,
  exerciseBall,
  foamRoll,
  kettlebells,
  machine,
  medicineBall,
  other;

  /// The handful of members whose backend wire value (snake_case) differs
  /// from this enum's lowerCamelCase Dart name; every other member's wire
  /// value is just its [name]. See [MuscleGroup]'s own `_wireNames`.
  static const _wireNames = <Equipment, String>{
    Equipment.bodyOnly: 'body_only',
    Equipment.eZCurlBar: 'e_z_curl_bar',
    Equipment.exerciseBall: 'exercise_ball',
    Equipment.foamRoll: 'foam_roll',
    Equipment.medicineBall: 'medicine_ball',
  };

  static Equipment fromJson(String value) {
    for (final entry in _wireNames.entries) {
      if (entry.value == value) return entry.key;
    }
    return Equipment.values.byName(value);
  }

  String toJson() => _wireNames[this] ?? name;

  /// A human-readable label for chips/dropdowns, e.g. "E-Z curl bar".
  String get label {
    if (this == Equipment.eZCurlBar) return 'E-Z curl bar';
    final wire = toJson().replaceAll('_', ' ');
    return wire[0].toUpperCase() + wire.substring(1);
  }
}
