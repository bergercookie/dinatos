import 'package:dinatos_frontend/features/personas/persona_profiles.dart';
import 'package:dinatos_frontend/features/personas/persona_scoring.dart';
import 'package:dinatos_frontend/features/stats/training_stats.dart' show StatsRange;
import 'package:dinatos_frontend/models/activity.dart';
import 'package:dinatos_frontend/models/equipment.dart';
import 'package:dinatos_frontend/models/exercise.dart';
import 'package:dinatos_frontend/models/measurement.dart';
import 'package:dinatos_frontend/models/set_type.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 30, 12);

const _squat = Exercise(id: 1, name: 'Squat (Barbell)');
const _jump = Exercise(id: 2, name: 'Box Jump');
const _run = Exercise(id: 3, name: 'Running', tracksDistance: true, tracksDuration: true);
const _pullUp = Exercise(id: 4, name: 'Pull Up', equipment: Equipment.bodyOnly);
const _catalog = [_squat, _jump, _run, _pullUp];

Activity _workout(int exerciseId, List<ActivitySet> sets, {DateTime? at}) => Activity(
  title: 't',
  startedAt: at ?? DateTime(2026, 9, 28, 10),
  exercises: [ActivityExercise(exerciseId: exerciseId, sets: sets)],
);

ActivitySet _lift(double kg, int reps) => ActivitySet(weightKg: kg, reps: reps);

void main() {
  test('every persona has a training mix that adds up to 1', () {
    for (final p in personas) {
      expect(p.training.values.fold<double>(0, (a, b) => a + b), closeTo(1, 1e-9), reason: p.id);
      expect(p.training.keys.toSet(), TrainingFocus.values.toSet(), reason: p.id);
    }
  });

  group('computeBodyFeatures', () {
    test('derives ratios from the newest value of each field', () {
      final features = computeBodyFeatures([
        BodyMeasurement(measuredAt: DateTime(2026, 1, 1), weightKg: 90, waistCm: 100),
        BodyMeasurement(
          measuredAt: DateTime(2026, 6, 1),
          weightKg: 80,
          fatPercent: 10,
          waistCm: 80,
          shoulderCm: 120,
          leftThighCm: 60,
          rightThighCm: 62,
          rightBicepCm: 36,
        ),
      ], heightCm: 180);

      expect(features[BodyFeature.height], 180);
      // 80 kg at 10% fat = 72 kg lean, at 1.8 m.
      expect(features[BodyFeature.ffmi], closeTo(72 / 3.24, 1e-9));
      expect(features[BodyFeature.fatPercent], 10);
      expect(features[BodyFeature.waistToHeight], closeTo(80 / 180, 1e-9));
      expect(features[BodyFeature.shoulderToWaist], 1.5);
      // Two sides are averaged; one side alone is used as is.
      expect(features[BodyFeature.thighToHeight], closeTo(61 / 180, 1e-9));
      expect(features[BodyFeature.armToHeight], closeTo(36 / 180, 1e-9));
    });

    test('uses the smart scale\'s muscle mass and segmental muscle', () {
      final features = computeBodyFeatures([
        BodyMeasurement(
          measuredAt: DateTime(2026, 6, 1),
          muscleMassKg: 55.125,
          leftArmMuscleKg: 3,
          rightArmMuscleKg: 3.4,
          leftLegMuscleKg: 9,
          rightLegMuscleKg: 9.4,
        ),
      ], heightCm: 175);

      expect(features[BodyFeature.muscleIndex], closeTo(55.125 / 1.75 / 1.75, 1e-9));
      // Legs 9.2 against arms 3.2 (each averaged over both sides).
      expect(features[BodyFeature.lowerBodyMuscle], closeTo(9.2 / 12.4, 1e-9));
    });

    test('segmental muscle needs both an arm and a leg reading', () {
      final features = computeBodyFeatures([
        BodyMeasurement(measuredAt: DateTime(2026, 6, 1), rightArmMuscleKg: 3.2),
      ], heightCm: 175);
      expect(features.containsKey(BodyFeature.lowerBodyMuscle), isFalse);
      expect(features.containsKey(BodyFeature.muscleIndex), isFalse);
    });

    test('one logged side stands in for the limb', () {
      final features = computeBodyFeatures([
        BodyMeasurement(measuredAt: DateTime(2026, 6, 1), rightArmMuscleKg: 3, leftLegMuscleKg: 9),
      ]);
      expect(features[BodyFeature.lowerBodyMuscle], closeTo(0.75, 1e-9));
    });

    test('a field missing from the newest entry falls back to an older one', () {
      final features = computeBodyFeatures([
        BodyMeasurement(measuredAt: DateTime(2026, 1, 1), fatPercent: 15),
        BodyMeasurement(measuredAt: DateTime(2026, 6, 1), weightKg: 80),
      ], heightCm: 180);
      expect(features[BodyFeature.ffmi], isNotNull);
    });

    test('leaves out what cannot be worked out', () {
      expect(computeBodyFeatures(const []), isEmpty);
      final features = computeBodyFeatures([
        BodyMeasurement(measuredAt: DateTime(2026, 6, 1), waistCm: 80),
      ]);
      // A waist with no height or shoulders gives no ratio at all.
      expect(features, isEmpty);
    });
  });

  test('missingBodyInputs names what is not logged', () {
    expect(
      missingBodyInputs([
        BodyMeasurement(measuredAt: DateTime(2026, 6, 1), weightKg: 80, leftThighCm: 60),
      ], heightCm: null),
      [
        'height (in your profile)',
        'body fat %',
        'waist',
        'shoulders',
        'biceps',
        'muscle mass',
        'arm and leg muscle (segmental)',
      ],
    );
  });

  test('closeness is 1 on target and falls off with distance', () {
    const target = BodyTarget(10, 2);
    expect(closeness(10, target), 1);
    expect(closeness(12, target), closeTo(0.607, 0.001));
    expect(closeness(8, target), closeness(12, target));
    expect(closeness(16, target), lessThan(0.02));
  });

  group('classifySet', () {
    test('sorts weighted sets by rep range', () {
      expect(classifySet(_squat, _lift(140, 3))?.focus, TrainingFocus.maxStrength);
      expect(classifySet(_squat, _lift(100, 10))?.focus, TrainingFocus.muscleBuilding);
      expect(classifySet(_squat, _lift(40, 25))?.focus, TrainingFocus.endurance);
    });

    test('explosive exercise names win', () {
      expect(classifySet(_jump, const ActivitySet(reps: 8))?.focus, TrainingFocus.explosive);
      expect(classifySet(_jump, _lift(20, 5))?.focus, TrainingFocus.explosive);
    });

    test('bodyweight reps and holds are skill work', () {
      expect(
        classifySet(_pullUp, const ActivitySet(reps: 8))?.focus,
        TrainingFocus.bodyweightSkill,
      );
      expect(
        classifySet(_pullUp, const ActivitySet(durationSeconds: 60))?.focus,
        TrainingFocus.bodyweightSkill,
      );
    });

    test('cardio counts by time, not as a single set', () {
      final run = classifySet(_run, const ActivitySet(distanceKm: 5, durationSeconds: 30 * 60));
      expect(run?.focus, TrainingFocus.endurance);
      expect(run?.units, 10);
      // No time given: assume a 6 min/km pace.
      expect(classifySet(_run, const ActivitySet(distanceKm: 3))?.units, 6);
    });

    test('works without the catalog, and ignores empty sets', () {
      expect(classifySet(null, _lift(100, 5))?.focus, TrainingFocus.maxStrength);
      expect(classifySet(_squat, const ActivitySet()), isNull);
    });
  });

  group('TrainingMix', () {
    test('ignores warm-ups and sets outside the range', () {
      final mix = TrainingMix.compute(
        [
          _workout(1, [
            for (var i = 0; i < 12; i++) _lift(100, 3),
            const ActivitySet(weightKg: 20, reps: 10, setType: SetType.warmup),
          ]),
          _workout(1, [_lift(50, 10)], at: DateTime(2026, 1, 1)),
        ],
        catalog: _catalog,
        range: StatsRange.month,
        now: _now,
      );
      expect(mix.units, 12);
      expect(mix.share[TrainingFocus.maxStrength], 1);
      expect(mix.isEnough, isTrue);
    });

    test('with nothing logged the mix is empty and not enough to score', () {
      final mix = TrainingMix.compute(const [], now: _now);
      expect(mix.units, 0);
      expect(mix.share.values, everyElement(0));
      expect(mix.isEnough, isFalse);
    });
  });

  group('PersonaAnalysis', () {
    // A tall, very lean, narrow-waisted build with slim limbs.
    final runnerBody = [
      BodyMeasurement(
        measuredAt: DateTime(2026, 9, 1),
        weightKg: 62,
        fatPercent: 7,
        waistCm: 72,
        shoulderCm: 94,
        leftThighCm: 49,
        leftBicepCm: 28,
      ),
    ];

    test('a lean runner-shaped body matches distance runner best', () {
      final analysis = PersonaAnalysis.compute(
        activities: const [],
        measurements: runnerBody,
        heightCm: 175,
        now: _now,
      );
      expect(analysis.hasBody, isTrue);
      expect(analysis.hasTraining, isFalse);
      expect(analysis.bestBody?.persona.id, 'distance_runner');
      expect(analysis.bestTraining, isNull);
      for (final m in analysis.matches) {
        expect(m.bodyScore, inInclusiveRange(0, 100));
        expect(m.trainingScore, isNull);
      }
    });

    test('leg-heavy muscle favours a sprinter, upper-body-heavy a gymnast', () {
      PersonaMatch match(PersonaAnalysis a, String id) =>
          a.matches.firstWhere((m) => m.persona.id == id);
      PersonaAnalysis analyse(double armKg, double legKg) => PersonaAnalysis.compute(
        activities: const [],
        measurements: [
          BodyMeasurement(
            measuredAt: DateTime(2026, 9, 1),
            muscleMassKg: 58,
            rightArmMuscleKg: armKg,
            rightLegMuscleKg: legKg,
            // Enough other features to clear the minimum for a score.
            weightKg: 72,
            fatPercent: 9,
          ),
        ],
        heightCm: 176,
        now: _now,
      );

      final legHeavy = analyse(2.8, 9.6);
      final armHeavy = analyse(4.2, 8.8);
      expect(legHeavy.bodyFeatures[BodyFeature.lowerBodyMuscle], greaterThan(0.75));
      expect(armHeavy.bodyFeatures[BodyFeature.lowerBodyMuscle], lessThan(0.7));
      // The same body otherwise: only the limb split moves the two personas.
      final legGap = match(legHeavy, 'sprinter').bodyScore! - match(legHeavy, 'gymnast').bodyScore!;
      final armGap = match(armHeavy, 'sprinter').bodyScore! - match(armHeavy, 'gymnast').bodyScore!;
      expect(legGap, greaterThan(armGap));
      final row = match(
        legHeavy,
        'sprinter',
      ).bodyRows.firstWhere((r) => r.feature == BodyFeature.lowerBodyMuscle);
      expect(BodyFeature.lowerBodyMuscle.format(row.ideal), '77%');
    });

    test('too few measurements gives no body score but still lists the rows', () {
      final analysis = PersonaAnalysis.compute(
        activities: const [],
        measurements: [BodyMeasurement(measuredAt: DateTime(2026, 9, 1), fatPercent: 9)],
        now: _now,
      );
      expect(analysis.hasBody, isFalse);
      expect(analysis.matches.first.bodyScore, isNull);
      expect(analysis.matches.first.bodyRows, hasLength(1));
    });

    test('lots of running matches distance runner; a squat-heavy log matches lifters', () {
      final running = PersonaAnalysis.compute(
        activities: [
          _workout(3, [for (var i = 0; i < 5; i++) const ActivitySet(distanceKm: 8)]),
        ],
        measurements: const [],
        catalog: _catalog,
        now: _now,
      );
      expect(running.bestTraining?.persona.id, 'distance_runner');
      // All endurance against an archetype that is 75% endurance: 75% overlap.
      expect(running.bestTraining?.trainingScore, closeTo(75, 1e-9));

      final lifting = PersonaAnalysis.compute(
        activities: [
          _workout(1, [for (var i = 0; i < 20; i++) _lift(140, 3)]),
        ],
        measurements: const [],
        catalog: _catalog,
        now: _now,
      );
      expect(lifting.bestTraining?.persona.id, 'powerlifter');
    });

    test('training gaps are ordered largest first', () {
      final analysis = PersonaAnalysis.compute(
        activities: [
          _workout(1, [for (var i = 0; i < 12; i++) _lift(80, 10)]),
        ],
        measurements: const [],
        catalog: _catalog,
        now: _now,
      );
      final sprinter = analysis.matches.firstWhere((m) => m.persona.id == 'sprinter');
      // All muscle building: the biggest gap is having far more of it than a
      // sprinter does, then comes the explosive work they lack.
      expect(sprinter.trainingRows.first.focus, TrainingFocus.muscleBuilding);
      expect(sprinter.trainingRows.first.gap, closeTo(-0.90, 1e-9));
      expect(sprinter.trainingRows[1].focus, TrainingFocus.explosive);
      expect(sprinter.trainingRows[1].gap, closeTo(0.40, 1e-9));
      final gaps = [for (final r in sprinter.trainingRows) r.gap.abs()];
      expect([...gaps]..sort((a, b) => b.compareTo(a)), gaps);
    });
  });
}
