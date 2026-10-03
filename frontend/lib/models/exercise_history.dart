import 'activity.dart';
import 'set_type.dart';

/// One past session of an exercise: every set the caller logged against it in
/// a single activity. From `GET /exercises/{id}/history` (newest first); the
/// "last time" hint, the overload suggestion and the progress chart are all
/// computed from these -- see `features/progress/progression.dart`.
class ExerciseHistoryEntry {
  const ExerciseHistoryEntry({
    required this.activityId,
    required this.activityTitle,
    required this.startedAt,
    required this.sets,
  });

  factory ExerciseHistoryEntry.fromJson(Map<String, dynamic> json) => ExerciseHistoryEntry(
    activityId: json['activity_id'] as int,
    activityTitle: json['activity_title'] as String,
    startedAt: DateTime.parse(json['started_at'] as String),
    // Not `ActivitySet.fromJson`: these carry no set id or position.
    sets: (json['sets'] as List<dynamic>).map((raw) {
      final set = raw as Map<String, dynamic>;
      return ActivitySet(
        setType: SetType.fromJson(set['set_type'] as String),
        weightKg: (set['weight_kg'] as num?)?.toDouble(),
        reps: set['reps'] as int?,
        distanceKm: (set['distance_km'] as num?)?.toDouble(),
        durationSeconds: set['duration_seconds'] as int?,
        rpe: (set['rpe'] as num?)?.toDouble(),
      );
    }).toList(),
  );

  final int activityId;
  final String activityTitle;
  final DateTime startedAt;
  final List<ActivitySet> sets;
}
