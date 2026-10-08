import 'hevy_import_result.dart';

/// One Intervals.icu activity as offered for selection by
/// `POST /imports/intervals/preview`.
class IntervalsActivity {
  const IntervalsActivity({
    required this.id,
    required this.name,
    this.type,
    this.startedAt,
    this.durationSeconds,
    this.distanceKm,
    this.importable = true,
    this.unimportableReason,
    this.alreadyImported = false,
    this.possibleDuplicateOf,
  });

  factory IntervalsActivity.fromJson(Map<String, dynamic> json) => IntervalsActivity(
    id: json['id'] as String,
    name: json['name'] as String,
    type: json['type'] as String?,
    startedAt: json['started_at'] == null ? null : DateTime.parse(json['started_at'] as String),
    durationSeconds: json['duration_seconds'] as int?,
    distanceKm: (json['distance_km'] as num?)?.toDouble(),
    importable: json['importable'] as bool? ?? true,
    unimportableReason: json['unimportable_reason'] as String?,
    alreadyImported: json['already_imported'] as bool? ?? false,
    possibleDuplicateOf: json['possible_duplicate_of'] as String?,
  );

  final String id;
  final String name;
  final String? type;

  /// Wall-clock start as Intervals.icu records it; null only when unimportable.
  final DateTime? startedAt;
  final int? durationSeconds;
  final double? distanceKm;

  /// False for e.g. a Strava-sourced activity, which Intervals.icu only
  /// returns a stub for; [unimportableReason] says why.
  final bool importable;
  final String? unimportableReason;

  /// Imported from Intervals.icu before (and still in the log).
  final bool alreadyImported;

  /// Title of a Dinatos activity starting within 30 minutes of this one --
  /// likely the same workout recorded twice (e.g. already synced from Hevy).
  final String? possibleDuplicateOf;

  /// Whether it's ticked by default: only what is importable and not
  /// already in the log in one form or another.
  bool get selectedByDefault => importable && !alreadyImported && possibleDuplicateOf == null;
}

class IntervalsImportResult {
  const IntervalsImportResult({
    required this.activitiesCreated,
    required this.exercisesCreated,
    this.createdExercises = const [],
  });

  factory IntervalsImportResult.fromJson(Map<String, dynamic> json) => IntervalsImportResult(
    activitiesCreated: json['activities_created'] as int,
    exercisesCreated: json['exercises_created'] as int,
    createdExercises: (json['created_exercises'] as List<dynamic>? ?? const [])
        .map((exercise) => ImportedExercise.fromJson(exercise as Map<String, dynamic>))
        .toList(),
  );

  final int activitiesCreated;
  final int exercisesCreated;
  final List<ImportedExercise> createdExercises;
}
