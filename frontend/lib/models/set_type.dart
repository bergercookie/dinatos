/// Mirrors `dinatos_backend.models.workout.SetType` -- shared by both
/// planned sets (in a workout) and performed sets (in an activity).
enum SetType {
  normal,
  warmup,
  dropset,
  failure;

  static SetType fromJson(String value) => SetType.values.byName(value);

  String toJson() => name;
}
