import 'package:dinatos_frontend/models/activity.dart';
import 'package:dinatos_frontend/models/exercise_tutorial.dart';
import 'package:dinatos_frontend/models/hevy_import_result.dart';
import 'package:dinatos_frontend/models/set_type.dart';
import 'package:dinatos_frontend/models/routine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Routine', () {
    test('round-trips through fromJson/toJson for a nested exercise/set', () {
      final json = {
        'id': 1,
        'name': 'Push day',
        'description': 'Chest, shoulders, triceps',
        'exercises': [
          {
            'id': 10,
            'position': 0,
            'exercise_id': 5,
            'notes': null,
            'sets': [
              {
                'id': 100,
                'position': 0,
                'set_type': 'warmup',
                'target_weight_kg': 40.0,
                'target_reps': 12,
                'target_distance_km': null,
                'target_duration_seconds': null,
              },
            ],
          },
        ],
      };

      final routine = Routine.fromJson(json);

      expect(routine.name, 'Push day');
      expect(routine.exercises, hasLength(1));
      expect(routine.exercises.single.sets.single.setType, SetType.warmup);
      expect(routine.exercises.single.sets.single.targetWeightKg, 40.0);

      // toJson() is the create/replace body -- it never re-emits server-
      // assigned ids, only what the API accepts back.
      final body = routine.toJson();
      expect(body, isNot(contains('id')));
      expect(body['exercises'], hasLength(1));
      expect((body['exercises'] as List).single, isNot(contains('id')));
    });

    test("RoutineSet.copyWith(targetWeightKg: null) clears it, doesn't keep the old value", () {
      const original = RoutineSet(targetWeightKg: 40);
      final cleared = original.copyWith(targetWeightKg: null);
      expect(cleared.targetWeightKg, isNull);
    });
  });

  group('Activity', () {
    test('parses started_at/ended_at as UTC-aware DateTimes', () {
      final activity = Activity.fromJson({
        'id': 1,
        'title': 'Morning run',
        'description': null,
        'started_at': '2026-01-01T08:00:00Z',
        'ended_at': '2026-01-01T08:30:00Z',
        'routine_id': null,
        'exercises': [],
      });

      expect(activity.startedAt.isUtc, isTrue);
      expect(activity.endedAt!.difference(activity.startedAt), const Duration(minutes: 30));
    });

    test('ActivitySet.copyWith(reps: null) clears it', () {
      const original = ActivitySet(reps: 8);
      expect(original.copyWith(reps: null).reps, isNull);
    });
  });

  group('ExerciseTutorial', () {
    test('parses the snake_case fields the backend actually sends', () {
      final tutorial = ExerciseTutorial.fromJson({
        'source': 'free_exercise_db',
        'gif_urls': ['https://example.com/a.jpg', 'https://example.com/b.jpg'],
        'instructions': ['Get in position.', 'Do the movement.'],
        'equipment': 'barbell',
        'primary_muscles': ['quadriceps'],
        'secondary_muscles': ['glutes', 'hamstrings'],
      });

      expect(tutorial.source, 'free_exercise_db');
      expect(tutorial.gifUrls, hasLength(2));
      expect(tutorial.instructions, ['Get in position.', 'Do the movement.']);
      expect(tutorial.equipment, 'barbell');
      expect(tutorial.secondaryMuscles, ['glutes', 'hamstrings']);
    });

    test('a null equipment (e.g. a bodyweight exercise) round-trips as null', () {
      final tutorial = ExerciseTutorial.fromJson({
        'source': 'workoutx',
        'gif_urls': <String>[],
        'instructions': <String>[],
        'equipment': null,
        'primary_muscles': <String>[],
        'secondary_muscles': <String>[],
      });

      expect(tutorial.equipment, isNull);
      expect(tutorial.gifUrls, isEmpty);
    });
  });

  group('HevyWorkoutImportResult/HevyMeasurementImportResult', () {
    test('parse the backend\'s snake_case counts', () {
      final workouts = HevyWorkoutImportResult.fromJson({
        'activities_created': 75,
        'exercises_created': 3,
      });
      expect(workouts.activitiesCreated, 75);
      expect(workouts.exercisesCreated, 3);

      final measurements = HevyMeasurementImportResult.fromJson({'measurements_created': 12});
      expect(measurements.measurementsCreated, 12);
    });
  });
}
