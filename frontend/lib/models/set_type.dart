/// Mirrors `dinatos_backend.models.routine.SetType` -- shared by both
/// planned sets (in a routine) and performed sets (in an activity).
enum SetType {
  normal,
  warmup,
  dropset,
  failure;

  static SetType fromJson(String value) => SetType.values.byName(value);

  /// The order a tap on a set's type label steps through: warm-up first, as
  /// that is how a session goes, then back around.
  static const cycle = [SetType.warmup, SetType.normal, SetType.dropset, SetType.failure];

  SetType get next => cycle[(cycle.indexOf(this) + 1) % cycle.length];

  /// One letter for the compact label on a set row.
  String get letter => name[0].toUpperCase();

  String toJson() => name;
}
