import 'dart:math' as math;

import '../../models/activity.dart';
import '../../models/exercise_history.dart';
import '../../models/set_type.dart';

/// Everything here is pure: it reads an exercise's history (as the backend
/// returns it, newest session first) and answers "how is this lift going?"
/// -- the per-session numbers behind the progress chart, a suggestion for the
/// next session, and whether progress has stalled.

/// Sets beyond this many reps are left out of the estimated one-rep max: the
/// Epley formula is only a reasonable guess for lower-rep sets.
const maxRepsForEstimate = 12;

/// How many sessions in a row without a new best before [detectPlateau] calls
/// it a plateau.
const plateauSessions = 4;

/// The weight below which [weightIncrementFor] steps by 1 kg instead of 2.5.
const _smallLoadKg = 20.0;

/// Warm-ups say nothing about how strong the person is.
bool _isWorking(ActivitySet set) => set.setType != SetType.warmup;

/// Epley's estimated one-rep max, or null when the set can't give one (no
/// load, no reps, or too many reps to extrapolate from).
double? estimateOneRepMax(double? weightKg, int? reps) {
  if (weightKg == null || reps == null || weightKg <= 0 || reps <= 0) return null;
  if (reps > maxRepsForEstimate) return null;
  return reps == 1 ? weightKg : weightKg * (1 + reps / 30);
}

/// One session's headline numbers for an exercise.
class SessionStats {
  const SessionStats({
    required this.date,
    required this.title,
    required this.workingSets,
    required this.volumeKg,
    this.topWeightKg,
    this.topWeightReps,
    this.bestReps,
    this.bestOneRepMaxKg,
  });

  final DateTime date;
  final String title;
  final int workingSets;

  /// Sum of weight x reps over the working sets.
  final double volumeKg;

  /// The heaviest working set (ties: the one with more reps).
  final double? topWeightKg;
  final int? topWeightReps;

  /// Most reps in any working set.
  final int? bestReps;
  final double? bestOneRepMaxKg;

  /// What "better" means for this exercise: the estimated 1RM when a load was
  /// used, otherwise the most reps in a set (a body-weight exercise).
  double? get performance => bestOneRepMaxKg ?? bestReps?.toDouble();
}

SessionStats summarizeSession(ExerciseHistoryEntry entry) {
  final working = entry.sets.where(_isWorking).toList();
  double volume = 0;
  double? topWeight;
  int? topReps;
  int? bestReps;
  double? bestE1rm;
  for (final set in working) {
    final weight = set.weightKg;
    final reps = set.reps;
    if (reps != null && (bestReps == null || reps > bestReps)) bestReps = reps;
    if (weight != null && reps != null) volume += weight * reps;
    if (weight != null && weight > 0) {
      if (topWeight == null ||
          weight > topWeight ||
          (weight == topWeight && (reps ?? 0) > (topReps ?? 0))) {
        topWeight = weight;
        topReps = reps;
      }
    }
    final e1rm = estimateOneRepMax(weight, reps);
    if (e1rm != null && (bestE1rm == null || e1rm > bestE1rm)) bestE1rm = e1rm;
  }
  return SessionStats(
    date: entry.startedAt,
    title: entry.activityTitle,
    workingSets: working.length,
    volumeKg: volume,
    topWeightKg: topWeight,
    topWeightReps: topReps,
    bestReps: bestReps,
    bestOneRepMaxKg: bestE1rm,
  );
}

/// [history] (newest first, as served) as oldest-first stats, dropping
/// sessions with no working set at all.
List<SessionStats> sessionTimeline(List<ExerciseHistoryEntry> history) => [
  for (final entry in history.reversed)
    if (entry.sets.any(_isWorking)) summarizeSession(entry),
];

/// How much to add to [weightKg] when the next step up is due.
double weightIncrementFor(double weightKg) => weightKg < _smallLoadKg ? 1.0 : 2.5;

enum SuggestionKind {
  /// Every set hit its target: add weight.
  increaseWeight,

  /// The target wasn't met on every set, or it was a hard effort: same
  /// weight again, aiming for the best set's reps on all of them.
  repeatWeight,

  /// A body-weight exercise: one more rep.
  addRep,
}

class OverloadSuggestion {
  const OverloadSuggestion({
    required this.kind,
    required this.setCount,
    required this.reps,
    this.weightKg,
    required this.lastSummary,
    required this.advice,
  });

  final SuggestionKind kind;

  /// How many working sets the last session had -- and so how many to aim for.
  final int setCount;
  final double? weightKg;
  final int reps;

  /// "3 × 8 @ 60 kg": what was done last time.
  final String lastSummary;

  /// What to do next, as a short sentence: "Try 62.5 kg × 8."
  final String advice;

  /// [lastSummary] and [advice] as one sentence, for where there is room.
  String get message => 'Last time $lastSummary. $advice';
}

String formatKg(double kg) => kg == kg.roundToDouble() ? kg.toStringAsFixed(0) : kg.toString();

/// "3 × 8 @ 60 kg", "3 × 8, 8, 6 @ 60 kg" when the sets differed, or just
/// "3 × 10" for a body-weight exercise: [sets] collapsed to the shortest
/// readable description.
String describeSets(List<ActivitySet> sets) {
  final working = sets.where(_isWorking).where((s) => s.reps != null).toList();
  if (working.isEmpty) return '';
  final weights = working.map((s) => s.weightKg).toSet();
  if (weights.length > 1) {
    // A different weight per set: list each as weight × reps.
    return working
        .map((s) => '${s.weightKg == null ? '' : '${formatKg(s.weightKg!)}×'}${s.reps}')
        .join(', ');
  }
  final reps = working.map((s) => s.reps!).toList();
  final base = reps.toSet().length == 1
      ? '${working.length} × ${reps.first}'
      : '${reps.join(', ')} reps';
  final weight = weights.single;
  return weight != null && weight > 0 ? '$base @ ${formatKg(weight)} kg' : base;
}

/// A suggestion for the next session of an exercise, from its most recent one
/// ([last]) -- a simple double progression:
///
/// * if every working set at the top weight got the same number of reps (the
///   target was met on all of them), add weight, aiming for those reps again;
/// * otherwise stay at that weight and aim for the best set's reps on every set;
/// * a body-weight exercise just adds a rep.
///
/// Null when the last session has no usable working set.
OverloadSuggestion? suggestOverload(ExerciseHistoryEntry? last) {
  if (last == null) return null;
  final nonWarmup = last.sets.where(_isWorking).where((s) => (s.reps ?? 0) > 0).toList();
  // Drop sets and failure sets are not a baseline to build on, unless that's all there is.
  final normal = nonWarmup.where((s) => s.setType == SetType.normal).toList();
  final basis = normal.isNotEmpty ? normal : nonWarmup;
  if (basis.isEmpty) return null;

  final loaded = basis.where((s) => (s.weightKg ?? 0) > 0).toList();
  final summary = describeSets(basis);

  if (loaded.isEmpty) {
    final best = basis.map((s) => s.reps!).reduce(math.max);
    return OverloadSuggestion(
      kind: SuggestionKind.addRep,
      setCount: basis.length,
      reps: best + 1,
      lastSummary: summary,
      advice: 'Try ${best + 1} reps.',
    );
  }

  final topWeight = loaded.map((s) => s.weightKg!).reduce(math.max);
  final atTop = loaded.where((s) => s.weightKg == topWeight).toList();
  final reps = atTop.map((s) => s.reps!).toList();
  final maxReps = reps.reduce(math.max);
  final allHit = reps.every((r) => r == maxReps);
  final setCount = basis.length;

  if (allHit) {
    final next = topWeight + weightIncrementFor(topWeight);
    return OverloadSuggestion(
      kind: SuggestionKind.increaseWeight,
      setCount: setCount,
      weightKg: next,
      reps: maxReps,
      lastSummary: summary,
      advice: 'Try ${formatKg(next)} kg × $maxReps.',
    );
  }
  return OverloadSuggestion(
    kind: SuggestionKind.repeatWeight,
    setCount: setCount,
    weightKg: topWeight,
    reps: maxReps,
    lastSummary: summary,
    advice: 'Stay at ${formatKg(topWeight)} kg and aim for $maxReps on every set.',
  );
}

/// [exercise]'s sets with [suggestion] filled in: every working set that has
/// no value yet gets the suggested weight and reps; with no sets at all,
/// [OverloadSuggestion.setCount] of them are created. Sets the person already
/// filled in are left alone.
List<ActivitySet> applySuggestion(
  List<ActivitySet> sets,
  OverloadSuggestion suggestion, {
  required ActivitySet Function() newSet,
}) {
  final base = sets.isEmpty ? [for (var i = 0; i < suggestion.setCount; i++) newSet()] : sets;
  return [
    for (final set in base)
      if (set.setType == SetType.warmup)
        set
      else
        set.copyWith(
          weightKg: set.weightKg ?? suggestion.weightKg,
          reps: set.reps ?? suggestion.reps,
        ),
  ];
}

class Plateau {
  const Plateau({
    required this.sessionsSinceBest,
    required this.bestDate,
    required this.best,
    required this.isOneRepMax,
  });

  /// Sessions since the best one (not counting it).
  final int sessionsSinceBest;
  final DateTime bestDate;

  /// The best [SessionStats.performance]: kg when [isOneRepMax], else reps.
  final double best;
  final bool isOneRepMax;
}

/// A plateau when the best session ever (by [SessionStats.performance]) is at
/// least [plateauSessions] sessions behind the latest -- no new best since.
/// Needs more than that many sessions, so a lift with only a short history
/// never reads as stalled. The earliest session at the best value counts as
/// the best, so merely matching it again doesn't restart the clock.
Plateau? detectPlateau(List<ExerciseHistoryEntry> history, {int window = plateauSessions}) {
  final timeline = sessionTimeline(history).where((s) => s.performance != null).toList();
  if (timeline.length <= window) return null;
  var bestIndex = 0;
  for (var i = 1; i < timeline.length; i++) {
    // Beating the best by under half a percent is noise, not progress.
    if (timeline[i].performance! > timeline[bestIndex].performance! * 1.005) bestIndex = i;
  }
  final since = timeline.length - 1 - bestIndex;
  if (since < window) return null;
  final best = timeline[bestIndex];
  return Plateau(
    sessionsSinceBest: since,
    bestDate: best.date,
    best: best.performance!,
    isOneRepMax: best.bestOneRepMaxKg != null,
  );
}
