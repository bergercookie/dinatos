/// The caller's own all-time best weight and best reps for one exercise,
/// across every past logged set -- `null` means no past set ever recorded
/// that measure, not that it was beaten. Fetched at the end of a live
/// workout to detect a new personal record; see
/// `features/activities/live/activity_summary_screen.dart`.
class ExerciseRecords {
  const ExerciseRecords({this.maxWeightKg, this.maxReps});

  factory ExerciseRecords.fromJson(Map<String, dynamic> json) => ExerciseRecords(
    maxWeightKg: (json['max_weight_kg'] as num?)?.toDouble(),
    maxReps: json['max_reps'] as int?,
  );

  final double? maxWeightKg;
  final int? maxReps;
}
