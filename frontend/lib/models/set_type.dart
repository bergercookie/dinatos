/// Mirrors `dinatos_backend.models.routine.SetType` -- shared by both
/// planned sets (in a routine) and performed sets (in an activity).
enum SetType {
  normal,
  warmup,
  dropset,
  failure;

  static SetType fromJson(String value) => SetType.values.byName(value);

  String toJson() => name;
}
