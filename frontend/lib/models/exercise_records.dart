import 'activity.dart';
import 'set_type.dart';

/// The caller's own all-time best weight and best reps for one exercise,
/// across every past logged working set (warm-ups never count) -- `null`
/// means no past set ever recorded that measure, not that it was beaten.
/// Compared against what's being logged to detect a new personal record; see
/// [detectSetRecords] and `features/activities/live/activity_summary_screen.dart`.
class ExerciseRecords {
  const ExerciseRecords({this.maxWeightKg, this.maxReps});

  factory ExerciseRecords.fromJson(Map<String, dynamic> json) => ExerciseRecords(
    maxWeightKg: (json['max_weight_kg'] as num?)?.toDouble(),
    maxReps: json['max_reps'] as int?,
  );

  final double? maxWeightKg;
  final int? maxReps;

  bool get isEmpty => maxWeightKg == null && maxReps == null;
}

/// Which personal records one set just set.
class SetRecord {
  const SetRecord({this.weight = false, this.reps = false});

  /// Heaviest weight yet for this exercise.
  final bool weight;

  /// Most reps yet, for a set with no load (a body-weight set) -- a rep count
  /// at some weight says little about how many a lighter set could do.
  final bool reps;

  bool get any => weight || reps;
}

/// For each of [sets] (in the order done), whether it beat [prior] *and* every
/// earlier set in the list -- so only the set that first reaches a new best is
/// flagged, not each later one at the same number. Warm-ups are never
/// records. With [requirePrior], an exercise with no history at all flags
/// nothing (there is nothing yet to have beaten); without it, the first
/// logged set of an exercise counts as setting its record.
List<SetRecord> detectSetRecords(
  List<ActivitySet> sets,
  ExerciseRecords prior, {
  bool requirePrior = true,
}) {
  double? bestWeight = prior.maxWeightKg;
  int? bestReps = prior.maxReps;
  final hadWeight = bestWeight != null;
  final hadReps = bestReps != null;
  final flags = <SetRecord>[];
  for (final set in sets) {
    if (set.setType == SetType.warmup) {
      flags.add(const SetRecord());
      continue;
    }
    final weight = set.weightKg;
    final reps = set.reps;
    final loaded = weight != null && weight > 0;
    var weightRecord = false;
    var repsRecord = false;
    if (loaded && (bestWeight == null || weight > bestWeight)) {
      weightRecord = !requirePrior || hadWeight;
      bestWeight = weight;
    }
    if (!loaded && reps != null && reps > 0 && (bestReps == null || reps > bestReps)) {
      repsRecord = !requirePrior || hadReps;
      bestReps = reps;
    }
    flags.add(SetRecord(weight: weightRecord, reps: repsRecord));
  }
  return flags;
}
