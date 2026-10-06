import 'dart:math' as math;

import '../../models/activity.dart';
import '../../models/equipment.dart';
import '../../models/exercise.dart';
import '../../models/measurement.dart';
import '../../models/set_type.dart';
import '../stats/training_stats.dart' show StatsRange;
import 'persona_profiles.dart';

/// How many body features must be known before a body match is worth
/// showing. Fewer than this and a "match" would be mostly guesswork.
const minBodyFeatures = 3;

/// How much logged training (in set-equivalents, see [classifySet]) the
/// training match needs before it means anything.
const minTrainingUnits = 10.0;

/// A cardio set is one long effort rather than a handful of reps, so it is
/// counted as one set-equivalent per this many minutes -- otherwise a whole
/// hour of running would weigh the same as a single bench press set.
const _minutesPerSetEquivalent = 3.0;

/// Pace assumed to turn a distance with no time into minutes.
const _minutesPerKm = 6.0;

final _explosiveName = RegExp(
  r'\b(jump|clean|snatch|jerk|throw|sprint|plyo|swing|bound|slam|burpee)',
  caseSensitive: false,
);

/// The most recent logged value of each body feature, or nothing for a
/// feature that can't be worked out.
///
/// People log whatever they measured that day, so each underlying field comes
/// from the newest measurement that has it rather than from the newest one
/// alone; height is a profile setting, not a measurement.
Map<BodyFeature, double> computeBodyFeatures(
  List<BodyMeasurement> measurements, {
  double? heightCm,
}) {
  final newestFirst = [...measurements]..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
  double? latest(double? Function(BodyMeasurement m) field) {
    for (final m in newestFirst) {
      final value = field(m);
      if (value != null && value > 0) return value;
    }
    return null;
  }

  // Left and right of the same limb are averaged: they are rarely the same,
  // and one logged side is plenty.
  double? limb(
    double? Function(BodyMeasurement m) left,
    double? Function(BodyMeasurement m) right,
  ) {
    final l = latest(left);
    final r = latest(right);
    if (l != null && r != null) return (l + r) / 2;
    return l ?? r;
  }

  final height = heightCm != null && heightCm > 0 ? heightCm : null;
  final weight = latest((m) => m.weightKg);
  final fat = latest((m) => m.fatPercent);
  final waist = latest((m) => m.waistCm);
  final shoulder = latest((m) => m.shoulderCm);
  final thigh = limb((m) => m.leftThighCm, (m) => m.rightThighCm);
  final arm = limb((m) => m.leftBicepCm, (m) => m.rightBicepCm);
  final muscle = latest((m) => m.muscleMassKg);
  // The scale's segmental muscle readout: how much of the muscle in the limbs
  // sits in the legs. Needs at least one arm and one leg reading.
  final armMuscle = limb((m) => m.leftArmMuscleKg, (m) => m.rightArmMuscleKg);
  final legMuscle = limb((m) => m.leftLegMuscleKg, (m) => m.rightLegMuscleKg);

  return {
    BodyFeature.height: ?height,
    if (height != null && weight != null && fat != null && fat < 100)
      BodyFeature.ffmi: weight * (1 - fat / 100) / math.pow(height / 100, 2),
    BodyFeature.fatPercent: ?fat,
    if (height != null && waist != null) BodyFeature.waistToHeight: waist / height,
    if (shoulder != null && waist != null) BodyFeature.shoulderToWaist: shoulder / waist,
    if (height != null && thigh != null) BodyFeature.thighToHeight: thigh / height,
    if (height != null && arm != null) BodyFeature.armToHeight: arm / height,
    if (height != null && muscle != null)
      BodyFeature.muscleIndex: muscle / math.pow(height / 100, 2),
    if (armMuscle != null && legMuscle != null)
      BodyFeature.lowerBodyMuscle: legMuscle / (armMuscle + legMuscle),
  };
}

/// What to log to unlock more of the body match: the plain-language names of
/// the inputs that are missing and would add a feature.
List<String> missingBodyInputs(List<BodyMeasurement> measurements, {double? heightCm}) {
  bool has(double? Function(BodyMeasurement m) field) =>
      measurements.any((m) => (field(m) ?? 0) > 0);
  return [
    if (heightCm == null || heightCm <= 0) 'height (in your profile)',
    if (!has((m) => m.weightKg)) 'weight',
    if (!has((m) => m.fatPercent)) 'body fat %',
    if (!has((m) => m.waistCm)) 'waist',
    if (!has((m) => m.shoulderCm)) 'shoulders',
    if (!has((m) => m.leftThighCm) && !has((m) => m.rightThighCm)) 'thigh',
    if (!has((m) => m.leftBicepCm) && !has((m) => m.rightBicepCm)) 'biceps',
    if (!has((m) => m.muscleMassKg)) 'muscle mass',
    if (!(has((m) => m.leftArmMuscleKg) || has((m) => m.rightArmMuscleKg)) ||
        !(has((m) => m.leftLegMuscleKg) || has((m) => m.rightLegMuscleKg)))
      'arm and leg muscle (segmental)',
  ];
}

/// How close [value] is to a [target], from 0 (nowhere near) to 1 (spot on):
/// a bell curve one [BodyTarget.tolerance] wide.
double closeness(double value, BodyTarget target) {
  final distance = (value - target.ideal) / target.tolerance;
  return math.exp(-0.5 * distance * distance);
}

/// Which [TrainingFocus] one logged set counts towards, and how many
/// set-equivalents it is worth; null for a set that carries nothing to go on
/// (no weight, reps, distance or time).
///
/// [exercise] may be null (the catalog is still loading, or the exercise was
/// deleted): the set is then classified on its numbers alone.
({TrainingFocus focus, double units})? classifySet(Exercise? exercise, ActivitySet set) {
  final weight = set.weightKg ?? 0;
  final reps = set.reps ?? 0;
  final distance = set.distanceKm ?? 0;
  final seconds = set.durationSeconds ?? 0;
  final explosive = exercise != null && _explosiveName.hasMatch(exercise.name);

  if (weight > 0 && reps > 0) {
    if (explosive) return (focus: TrainingFocus.explosive, units: 1);
    if (reps <= 5) return (focus: TrainingFocus.maxStrength, units: 1);
    if (reps <= 15) return (focus: TrainingFocus.muscleBuilding, units: 1);
    return (focus: TrainingFocus.endurance, units: 1);
  }
  if (reps > 0) {
    if (explosive) return (focus: TrainingFocus.explosive, units: 1);
    if (reps > 30) return (focus: TrainingFocus.endurance, units: 1);
    return (focus: TrainingFocus.bodyweightSkill, units: 1);
  }
  if (seconds > 0 || distance > 0) {
    if (explosive) return (focus: TrainingFocus.explosive, units: 1);
    // A bodyweight hold (plank, hang) is skill and strength work, not cardio.
    if (distance == 0 && exercise?.equipment == Equipment.bodyOnly) {
      return (focus: TrainingFocus.bodyweightSkill, units: 1);
    }
    final minutes = seconds > 0 ? seconds / 60 : distance * _minutesPerKm;
    return (focus: TrainingFocus.endurance, units: math.max(1, minutes / _minutesPerSetEquivalent));
  }
  return null;
}

/// A person's training as a mix of [TrainingFocus] over the sets they logged.
class TrainingMix {
  const TrainingMix({required this.share, required this.units});

  /// Computes the mix over the activities that started within [range] of
  /// [now]. Warm-up sets don't count, same as the stats page.
  factory TrainingMix.compute(
    List<Activity> activities, {
    List<Exercise> catalog = const [],
    StatsRange range = StatsRange.all,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final days = range.days;
    final cutoff = days == null ? null : DateTime(clock.year, clock.month, clock.day - days + 1);
    final catalogById = {for (final e in catalog) e.id: e};

    final totals = {for (final f in TrainingFocus.values) f: 0.0};
    for (final activity in activities) {
      final started = activity.startedAt.toLocal();
      if (cutoff != null && DateTime(started.year, started.month, started.day).isBefore(cutoff)) {
        continue;
      }
      for (final entry in activity.exercises) {
        final exercise = catalogById[entry.exerciseId];
        for (final set in entry.completedSets) {
          if (set.setType == SetType.warmup) continue;
          final classified = classifySet(exercise, set);
          if (classified == null) continue;
          totals[classified.focus] = totals[classified.focus]! + classified.units;
        }
      }
    }
    final units = totals.values.fold<double>(0, (a, b) => a + b);
    return TrainingMix(
      share: {for (final f in TrainingFocus.values) f: units == 0 ? 0 : totals[f]! / units},
      units: units,
    );
  }

  /// Fraction of the logged work in each focus; sums to 1 (or all zero with
  /// no training).
  final Map<TrainingFocus, double> share;

  /// Total set-equivalents the mix is built from.
  final double units;

  bool get isEnough => units >= minTrainingUnits;
}

/// One row of a persona's body comparison: how this person's [feature]
/// compares with the persona's typical value.
class BodyRow {
  const BodyRow({
    required this.feature,
    required this.you,
    required this.ideal,
    required this.closeness,
  });

  final BodyFeature feature;
  final double you;
  final double ideal;

  /// 0 to 1, see [closeness].
  final double closeness;
}

/// One row of a persona's training comparison.
class TrainingRow {
  const TrainingRow({required this.focus, required this.you, required this.ideal});

  final TrainingFocus focus;

  /// Fractions (0 to 1) of the person's sets and of the persona's typical sets.
  final double you;
  final double ideal;

  /// Positive when the persona does more of this than the person.
  double get gap => ideal - you;
}

/// How one persona compares with the person, on both axes. A score is null
/// when there isn't enough data for it.
class PersonaMatch {
  const PersonaMatch({
    required this.persona,
    required this.bodyScore,
    required this.trainingScore,
    required this.bodyRows,
    required this.trainingRows,
  });

  final Persona persona;

  /// 0 to 100.
  final double? bodyScore;
  final double? trainingScore;

  /// Closest feature first.
  final List<BodyRow> bodyRows;

  /// Largest gap first, whichever direction it points.
  final List<TrainingRow> trainingRows;
}

PersonaMatch matchPersona(
  Persona persona, {
  required Map<BodyFeature, double> body,
  required TrainingMix training,
}) {
  final bodyRows = <BodyRow>[
    for (final entry in persona.body.entries)
      if (body[entry.key] != null)
        BodyRow(
          feature: entry.key,
          you: body[entry.key]!,
          ideal: entry.value.ideal,
          closeness: closeness(body[entry.key]!, entry.value),
        ),
  ]..sort((a, b) => b.closeness.compareTo(a.closeness));

  double? bodyScore;
  if (bodyRows.length >= minBodyFeatures) {
    var weighted = 0.0;
    var weights = 0.0;
    for (final row in bodyRows) {
      weighted += row.feature.weight * row.closeness;
      weights += row.feature.weight;
    }
    bodyScore = 100 * weighted / weights;
  }

  final trainingRows = <TrainingRow>[
    for (final focus in TrainingFocus.values)
      TrainingRow(
        focus: focus,
        you: training.share[focus] ?? 0,
        ideal: persona.training[focus] ?? 0,
      ),
  ]..sort((a, b) => b.gap.abs().compareTo(a.gap.abs()));

  double? trainingScore;
  if (training.isEnough) {
    // One minus the total variation distance: the share of the person's
    // training that already overlaps the persona's.
    final distance = trainingRows.fold<double>(0, (sum, r) => sum + r.gap.abs()) / 2;
    trainingScore = 100 * (1 - distance);
  }

  return PersonaMatch(
    persona: persona,
    bodyScore: bodyScore,
    trainingScore: trainingScore,
    bodyRows: bodyRows,
    trainingRows: trainingRows,
  );
}

/// The whole page's data: every persona's match plus the inputs behind it.
class PersonaAnalysis {
  const PersonaAnalysis({
    required this.matches,
    required this.bodyFeatures,
    required this.training,
    required this.missingInputs,
  });

  factory PersonaAnalysis.compute({
    required List<Activity> activities,
    required List<BodyMeasurement> measurements,
    List<Exercise> catalog = const [],
    double? heightCm,
    StatsRange range = StatsRange.quarter,
    DateTime? now,
  }) {
    final body = computeBodyFeatures(measurements, heightCm: heightCm);
    final training = TrainingMix.compute(activities, catalog: catalog, range: range, now: now);
    return PersonaAnalysis(
      matches: [for (final p in personas) matchPersona(p, body: body, training: training)],
      bodyFeatures: body,
      training: training,
      missingInputs: missingBodyInputs(measurements, heightCm: heightCm),
    );
  }

  final List<PersonaMatch> matches;
  final Map<BodyFeature, double> bodyFeatures;
  final TrainingMix training;

  /// Inputs that would unlock (more of) the body match.
  final List<String> missingInputs;

  bool get hasBody => matches.any((m) => m.bodyScore != null);
  bool get hasTraining => matches.any((m) => m.trainingScore != null);

  PersonaMatch? get bestBody => _best((m) => m.bodyScore);
  PersonaMatch? get bestTraining => _best((m) => m.trainingScore);

  PersonaMatch? _best(double? Function(PersonaMatch m) score) {
    PersonaMatch? best;
    for (final m in matches) {
      final s = score(m);
      if (s != null && (best == null || s > score(best)!)) best = m;
    }
    return best;
  }
}
