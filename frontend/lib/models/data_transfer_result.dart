/// What `POST /admin/backup/restore` reports.
class BackupRestoreResult {
  const BackupRestoreResult({required this.rows, required this.sessionKept});

  factory BackupRestoreResult.fromJson(Map<String, dynamic> json) => BackupRestoreResult(
    rows: (json['rows'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int)),
    sessionKept: json['session_kept'] as bool,
  );

  /// Rows restored, per table.
  final Map<String, int> rows;

  /// Whether the calling admin is still logged in -- if not, the app has to
  /// send them back to the login screen.
  final bool sessionKept;
}

/// How `POST /profile/import` treats what the account already has.
enum UserImportMode {
  merge,
  replace;

  String toJson() => name;
}

class ImportCounts {
  const ImportCounts({
    this.exercises = 0,
    this.routines = 0,
    this.activities = 0,
    this.measurements = 0,
  });

  factory ImportCounts.fromJson(Map<String, dynamic> json) => ImportCounts(
    exercises: json['exercises'] as int? ?? 0,
    routines: json['routines'] as int? ?? 0,
    activities: json['activities'] as int? ?? 0,
    measurements: json['measurements'] as int? ?? 0,
  );

  final int exercises;
  final int routines;
  final int activities;
  final int measurements;

  int get total => exercises + routines + activities + measurements;

  /// "2 routines, 1 activity" -- only the non-zero parts; "nothing" if none.
  String describe() {
    String part(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    final parts = [
      if (exercises > 0) part(exercises, 'exercise', 'exercises'),
      if (routines > 0) part(routines, 'routine', 'routines'),
      if (activities > 0) part(activities, 'activity', 'activities'),
      if (measurements > 0) part(measurements, 'measurement', 'measurements'),
    ];
    return parts.isEmpty ? 'nothing' : parts.join(', ');
  }
}

class UserImportResult {
  const UserImportResult({
    required this.mode,
    required this.created,
    required this.skipped,
    required this.deleted,
  });

  factory UserImportResult.fromJson(Map<String, dynamic> json) => UserImportResult(
    mode: UserImportMode.values.byName(json['mode'] as String),
    created: ImportCounts.fromJson(json['created'] as Map<String, dynamic>),
    skipped: ImportCounts.fromJson(json['skipped'] as Map<String, dynamic>),
    deleted: ImportCounts.fromJson(json['deleted'] as Map<String, dynamic>),
  );

  final UserImportMode mode;
  final ImportCounts created;
  final ImportCounts skipped;
  final ImportCounts deleted;

  /// One sentence for a snackbar.
  String summary() {
    final buffer = StringBuffer('Imported ${created.describe()}');
    if (skipped.total > 0) {
      buffer.write('; skipped ${skipped.describe()} already present');
    }
    if (deleted.total > 0) {
      buffer.write('; replaced ${deleted.describe()}');
    }
    return '$buffer.';
  }
}
