import 'dart:convert';
import 'dart:io';

import 'package:dinatos_frontend/features/personas/persona_profiles.dart';
import 'package:dinatos_frontend/features/personas/persona_scoring.dart';
import 'package:dinatos_frontend/features/stats/training_stats.dart' show StatsRange;
import 'package:dinatos_frontend/models/activity.dart';
import 'package:dinatos_frontend/models/exercise.dart';
import 'package:dinatos_frontend/models/measurement.dart';
import 'package:flutter_test/flutter_test.dart';

/// The same cases the backend's persona analysis (`services/personas.py`, behind
/// the MCP server's `get_persona_stats`) runs -- see
/// backend/tests/services/test_persona_parity.py. The two must agree.
const _bodyKeys = {
  BodyFeature.height: 'height',
  BodyFeature.ffmi: 'ffmi',
  BodyFeature.fatPercent: 'fat_percent',
  BodyFeature.waistToHeight: 'waist_to_height',
  BodyFeature.shoulderToWaist: 'shoulder_to_waist',
  BodyFeature.thighToHeight: 'thigh_to_height',
  BodyFeature.armToHeight: 'arm_to_height',
  BodyFeature.muscleIndex: 'muscle_index',
  BodyFeature.lowerBodyMuscle: 'lower_body_muscle',
};

const _focusKeys = {
  TrainingFocus.maxStrength: 'max_strength',
  TrainingFocus.muscleBuilding: 'muscle_building',
  TrainingFocus.explosive: 'explosive',
  TrainingFocus.endurance: 'endurance',
  TrainingFocus.bodyweightSkill: 'bodyweight_skill',
};

const _personaIds = {
  'sprinter',
  'distance_runner',
  'weightlifter',
  'powerlifter',
  'bodybuilder',
  'gymnast',
};

void main() {
  final document = jsonDecode(
    File('test/fixtures/persona_parity.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final now = DateTime.parse(document['now'] as String);

  test('the app has exactly the personas the backend has', () {
    expect({for (final p in personas) p.id}, _personaIds);
  });

  for (final raw in document['cases'] as List<dynamic>) {
    final testCase = raw as Map<String, dynamic>;
    test('agrees with the backend: ${testCase['name']}', () {
      final expected = testCase['expected'] as Map<String, dynamic>;
      final analysis = PersonaAnalysis.compute(
        activities: [
          for (final a in testCase['activities'] as List<dynamic>)
            Activity.fromJson(a as Map<String, dynamic>),
        ],
        measurements: [
          for (final m in testCase['measurements'] as List<dynamic>)
            BodyMeasurement.fromJson(m as Map<String, dynamic>),
        ],
        catalog: [
          for (final e in testCase['catalog'] as List<dynamic>)
            Exercise.fromJson(e as Map<String, dynamic>),
        ],
        heightCm: (testCase['height_cm'] as num?)?.toDouble(),
        range: StatsRange.values.byName(testCase['range'] as String),
        now: now,
      );

      final features = expected['body_features'] as Map<String, dynamic>;
      expect(
        {for (final e in analysis.bodyFeatures.entries) _bodyKeys[e.key]!: e.value}.keys.toSet(),
        features.keys.toSet(),
      );
      for (final e in analysis.bodyFeatures.entries) {
        expect(e.value, closeTo((features[_bodyKeys[e.key]] as num).toDouble(), 1e-9));
      }

      final shares = expected['training_share'] as Map<String, dynamic>;
      for (final e in analysis.training.share.entries) {
        expect(e.value, closeTo((shares[_focusKeys[e.key]] as num).toDouble(), 1e-9));
      }
      expect(
        analysis.training.units,
        closeTo((expected['training_units'] as num).toDouble(), 1e-9),
      );

      final scores = expected['personas'] as Map<String, dynamic>;
      for (final match in analysis.matches) {
        final want = scores[match.persona.id] as Map<String, dynamic>;
        for (final (name, got) in [
          ('body_score', match.bodyScore),
          ('training_score', match.trainingScore),
        ]) {
          final wanted = (want[name] as num?)?.toDouble();
          if (wanted == null) {
            expect(got, isNull, reason: '${match.persona.id} $name');
          } else {
            expect(got, closeTo(wanted, 1e-9), reason: '${match.persona.id} $name');
          }
        }
      }
      expect(analysis.bestBody?.persona.id, expected['best_body_match']);
      expect(analysis.bestTraining?.persona.id, expected['best_training_match']);
      expect(analysis.missingInputs, expected['missing_inputs']);
    });
  }
}
