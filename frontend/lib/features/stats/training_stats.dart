import 'dart:math' as math;

import '../../models/activity.dart';
import '../../models/exercise.dart';
import '../../models/muscle_group.dart';
import '../../models/set_type.dart';
import '../activities/live/muscle_volume.dart' show secondaryMuscleWeight;

/// How many Monday-start weeks the "workouts per week" chart covers.
const statsWeeklyChartWeeks = 12;

/// The time window the stats page summarizes.
enum StatsRange {
  month('30 days', 30),
  quarter('90 days', 90),
  year('1 year', 365),
  all('All time', null);

  const StatsRange(this.label, this.days);

  final String label;
  final int? days;
}

/// How often one exercise shows up in the activities summarized.
class ExerciseUsage {
  const ExerciseUsage({required this.name, required this.sessions, required this.sets});

  final String name;

  /// Distinct activities the exercise appears in.
  final int sessions;
  final int sets;
}

/// The best set for one exercise, by estimated one-rep max.
class LiftRecord {
  const LiftRecord({
    required this.name,
    required this.weightKg,
    required this.reps,
    required this.estimatedOneRepMaxKg,
  });

  final String name;
  final double weightKg;
  final int reps;
  final double estimatedOneRepMaxKg;
}

/// Epley's estimated one-rep max: `weight x (1 + reps / 30)`. A single is
/// already a one-rep max, so it is returned as is.
double estimateOneRepMax(double weightKg, int reps) =>
    reps <= 1 ? weightKg : weightKg * (1 + reps / 30);

DateTime _day(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// The Monday that starts [dt]'s week, built from calendar fields (not by
/// subtracting a [Duration]) so a DST change can't shift it off midnight.
DateTime _mondayOf(DateTime dt) => DateTime(dt.year, dt.month, dt.day - (dt.weekday - 1));

/// Everything the stats page and the home summary card show, derived purely
/// from already-loaded activities (and, for names and muscles, the exercise
/// catalog) -- there is no stats endpoint.
class TrainingStats {
  const TrainingStats({
    required this.workouts,
    required this.totalSets,
    required this.totalVolumeKg,
    required this.totalDuration,
    required this.timedWorkouts,
    required this.longestDuration,
    required this.workoutsPerWeek,
    required this.weekdayCounts,
    required this.weeklyCounts,
    required this.weekStarts,
    required this.muscleSets,
    required this.topExercises,
    required this.topLifts,
    required this.longestDayStreak,
  });

  /// Summarizes [activities] that started within [range] of [now]; the
  /// per-week chart ignores [range] and always shows the latest
  /// [statsWeeklyChartWeeks] weeks, so it stays a trend even on "30 days".
  /// [catalog] is only needed for exercise names and muscles; without it
  /// those sections come out empty.
  factory TrainingStats.compute(
    List<Activity> activities, {
    List<Exercise> catalog = const [],
    StatsRange range = StatsRange.all,
    DateTime? now,
  }) {
    final today = _day(now ?? DateTime.now());
    final rangeDays = range.days;
    final cutoff = rangeDays == null
        ? null
        : DateTime(today.year, today.month, today.day - rangeDays + 1);
    final inRange = [
      for (final a in activities)
        if (cutoff == null || !_day(a.startedAt.toLocal()).isBefore(cutoff)) a,
    ];

    final catalogById = {for (final e in catalog) e.id: e};

    var totalSets = 0;
    var totalVolume = 0.0;
    var totalDuration = Duration.zero;
    var timed = 0;
    var longest = Duration.zero;
    final weekdayCounts = List.filled(7, 0);
    final muscleSets = <MuscleGroup, double>{};
    final sessionsByExercise = <int, int>{};
    final setsByExercise = <int, int>{};
    final bestLift = <int, LiftRecord>{};

    for (final activity in inRange) {
      weekdayCounts[activity.startedAt.toLocal().weekday - 1]++;

      final endedAt = activity.endedAt;
      if (endedAt != null) {
        final duration = endedAt.difference(activity.startedAt);
        if (duration.inMinutes > 0) {
          totalDuration += duration;
          timed++;
          if (duration > longest) longest = duration;
        }
      }

      final seen = <int>{};
      for (final entry in activity.exercises) {
        final exercise = catalogById[entry.exerciseId];
        if (seen.add(entry.exerciseId)) {
          sessionsByExercise[entry.exerciseId] = (sessionsByExercise[entry.exerciseId] ?? 0) + 1;
        }
        for (final set in entry.sets) {
          totalSets++;
          setsByExercise[entry.exerciseId] = (setsByExercise[entry.exerciseId] ?? 0) + 1;
          final weight = set.weightKg ?? 0;
          final reps = set.reps ?? 0;
          if (set.setType == SetType.warmup) continue;

          if (weight > 0 && reps > 0) {
            totalVolume += weight * reps;
            final oneRepMax = estimateOneRepMax(weight, reps);
            final best = bestLift[entry.exerciseId];
            if (exercise != null && (best == null || oneRepMax > best.estimatedOneRepMaxKg)) {
              bestLift[entry.exerciseId] = LiftRecord(
                name: exercise.name,
                weightKg: weight,
                reps: reps,
                estimatedOneRepMaxKg: oneRepMax,
              );
            }
          }
          if (exercise == null) continue;
          for (final muscle in exercise.primaryMuscles) {
            muscleSets[muscle] = (muscleSets[muscle] ?? 0) + 1;
          }
          for (final muscle in exercise.secondaryMuscles) {
            muscleSets[muscle] = (muscleSets[muscle] ?? 0) + secondaryMuscleWeight;
          }
        }
      }
    }

    // Average over the span actually covered: from the start of the range,
    // but never earlier than the first logged workout (a new user shouldn't
    // be averaged against months before they started).
    var perWeek = 0.0;
    if (inRange.isNotEmpty) {
      final first = inRange
          .map((a) => _day(a.startedAt.toLocal()))
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final start = cutoff != null && cutoff.isAfter(first) ? cutoff : first;
      final days = today.difference(start).inDays + 1;
      perWeek = inRange.length / math.max(1, days / 7);
    }

    final thisMonday = _mondayOf(today);
    final weekStarts = [
      for (var i = statsWeeklyChartWeeks - 1; i >= 0; i--)
        DateTime(thisMonday.year, thisMonday.month, thisMonday.day - 7 * i),
    ];
    final weeklyCounts = List.filled(statsWeeklyChartWeeks, 0);
    for (final activity in activities) {
      final monday = _mondayOf(activity.startedAt.toLocal());
      final index = weekStarts.indexWhere((w) => w == monday);
      if (index >= 0) weeklyCounts[index]++;
    }

    final topExercises =
        <ExerciseUsage>[
          for (final entry in sessionsByExercise.entries)
            ExerciseUsage(
              name: catalogById[entry.key]?.name ?? 'Exercise #${entry.key}',
              sessions: entry.value,
              sets: setsByExercise[entry.key] ?? 0,
            ),
        ]..sort((a, b) {
          final bySessions = b.sessions.compareTo(a.sessions);
          if (bySessions != 0) return bySessions;
          final bySets = b.sets.compareTo(a.sets);
          return bySets != 0 ? bySets : a.name.compareTo(b.name);
        });

    final topLifts = bestLift.values.toList()
      ..sort((a, b) => b.estimatedOneRepMaxKg.compareTo(a.estimatedOneRepMaxKg));

    return TrainingStats(
      workouts: inRange.length,
      totalSets: totalSets,
      totalVolumeKg: totalVolume,
      totalDuration: totalDuration,
      timedWorkouts: timed,
      longestDuration: longest,
      workoutsPerWeek: perWeek,
      weekdayCounts: weekdayCounts,
      weeklyCounts: weeklyCounts,
      weekStarts: weekStarts,
      muscleSets: muscleSets,
      topExercises: topExercises,
      topLifts: topLifts,
      longestDayStreak: _longestDayStreak({for (final a in inRange) _day(a.startedAt.toLocal())}),
    );
  }

  final int workouts;
  final int totalSets;

  /// Sum of weight x reps over every non-warmup set that has both.
  final double totalVolumeKg;
  final Duration totalDuration;

  /// Workouts with a usable end time -- the denominator for [averageDuration].
  final int timedWorkouts;
  final Duration longestDuration;
  final double workoutsPerWeek;

  /// Workouts per weekday, Monday first.
  final List<int> weekdayCounts;

  /// Workouts in each of the latest [statsWeeklyChartWeeks] weeks, oldest
  /// first; [weekStarts] holds each week's Monday.
  final List<int> weeklyCounts;
  final List<DateTime> weekStarts;

  /// Working sets per muscle: a primary muscle gets 1 per set, a secondary
  /// one [secondaryMuscleWeight]. Warm-up sets don't count.
  final Map<MuscleGroup, double> muscleSets;

  /// Most-performed first.
  final List<ExerciseUsage> topExercises;

  /// Heaviest estimated one-rep max first.
  final List<LiftRecord> topLifts;
  final int longestDayStreak;

  Duration? get averageDuration => timedWorkouts == 0 ? null : totalDuration ~/ timedWorkouts;
}

int _longestDayStreak(Set<DateTime> days) {
  final sorted = days.toList()..sort();
  var longest = 0;
  var run = 0;
  DateTime? previous;
  for (final day in sorted) {
    // Compare calendar fields rather than a Duration so DST can't break a run.
    final consecutive =
        previous != null && DateTime(previous.year, previous.month, previous.day + 1) == day;
    run = consecutive ? run + 1 : 1;
    if (run > longest) longest = run;
    previous = day;
  }
  return longest;
}

/// "1h 05m" / "45 min".
String formatDuration(Duration d) {
  final minutes = d.inMinutes;
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}

/// "820 kg" / "12.4 t" -- tonnes once it gets big enough to read better.
String formatWeight(double kg) {
  if (kg >= 10000) return '${(kg / 1000).toStringAsFixed(1)} t';
  return '${kg.round()} kg';
}
