import 'package:dinatos_frontend/models/activity.dart';
import 'package:dinatos_frontend/models/equipment.dart';
import 'package:dinatos_frontend/models/exercise.dart';
import 'package:dinatos_frontend/models/exercise_tutorial.dart';
import 'package:dinatos_frontend/models/hevy_import_result.dart';
import 'package:dinatos_frontend/models/muscle_group.dart';
import 'package:dinatos_frontend/models/set_type.dart';
import 'package:dinatos_frontend/models/routine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _completedTests();
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

  group('Exercise', () {
    test('parses the backend\'s equipment/muscle fields', () {
      final exercise = Exercise.fromJson({
        'id': 1,
        'name': 'Barbell Deadlift',
        'tracks_weight': true,
        'tracks_reps': true,
        'tracks_distance': false,
        'tracks_duration': false,
        'is_custom': false,
        'equipment': 'barbell',
        'primary_muscles': ['lower_back'],
        'secondary_muscles': ['glutes', 'hamstrings'],
      });

      expect(exercise.equipment, Equipment.barbell);
      expect(exercise.primaryMuscles, [MuscleGroup.lowerBack]);
      expect(exercise.secondaryMuscles, [MuscleGroup.glutes, MuscleGroup.hamstrings]);
    });

    test('a null equipment and empty muscle lists round-trip as such', () {
      final exercise = Exercise.fromJson({
        'id': 2,
        'name': 'Plank',
        'tracks_weight': false,
        'tracks_reps': false,
        'tracks_distance': false,
        'tracks_duration': true,
        'is_custom': true,
        'equipment': null,
        'primary_muscles': <String>[],
        'secondary_muscles': <String>[],
      });

      expect(exercise.equipment, isNull);
      expect(exercise.primaryMuscles, isEmpty);
      expect(exercise.secondaryMuscles, isEmpty);
    });

    test('toJson() sends the wire-cased equipment/muscle values back', () {
      const exercise = Exercise(
        name: 'Barbell Deadlift',
        equipment: Equipment.eZCurlBar,
        primaryMuscles: [MuscleGroup.lowerBack],
        secondaryMuscles: [MuscleGroup.middleBack],
      );

      final body = exercise.toJson();

      expect(body['equipment'], 'e_z_curl_bar');
      expect(body['primary_muscles'], ['lower_back']);
      expect(body['secondary_muscles'], ['middle_back']);
    });
  });

  group('MuscleGroup/Equipment', () {
    test('every member round-trips through toJson/fromJson', () {
      for (final muscle in MuscleGroup.values) {
        expect(MuscleGroup.fromJson(muscle.toJson()), muscle);
      }
      for (final equipment in Equipment.values) {
        expect(Equipment.fromJson(equipment.toJson()), equipment);
      }
    });

    test('the wire value matches the backend\'s snake_case spelling', () {
      expect(MuscleGroup.lowerBack.toJson(), 'lower_back');
      expect(MuscleGroup.middleBack.toJson(), 'middle_back');
      expect(Equipment.bodyOnly.toJson(), 'body_only');
      expect(Equipment.eZCurlBar.toJson(), 'e_z_curl_bar');
    });
  });

  group('HevyWorkoutImportResult/HevyMeasurementImportResult', () {
    test('parse the created exercises with their guessed flags', () {
      final workouts = HevyWorkoutImportResult.fromJson({
        'activities_created': 1,
        'exercises_created': 2,
        'created_exercises': [
          {
            'id': 7,
            'name': 'Zottman Curl (Dumbbell)',
            'equipment': 'dumbbell',
            'primary_muscles': ['biceps'],
            'secondary_muscles': ['lower_back'],
            'equipment_guessed': true,
            'muscles_guessed': true,
          },
          {'id': 8, 'name': 'Homemade Thing'},
        ],
      });

      final guessed = workouts.createdExercises.first;
      expect(guessed.id, 7);
      expect(guessed.equipment, Equipment.dumbbell);
      expect(guessed.primaryMuscles, [MuscleGroup.biceps]);
      expect(guessed.secondaryMuscles, [MuscleGroup.lowerBack]);
      expect(guessed.equipmentGuessed, isTrue);
      expect(guessed.musclesGuessed, isTrue);

      final bare = workouts.createdExercises.last;
      expect(bare.equipment, isNull);
      expect(bare.primaryMuscles, isEmpty);
      expect(bare.equipmentGuessed, isFalse);
      expect(bare.musclesGuessed, isFalse);
    });

    test('parse the backend\'s snake_case counts', () {
      final workouts = HevyWorkoutImportResult.fromJson({
        'activities_created': 75,
        'exercises_created': 3,
      });
      expect(workouts.activitiesCreated, 75);
      expect(workouts.exercisesCreated, 3);
      // Older backends send no created_exercises: it defaults to empty.
      expect(workouts.createdExercises, isEmpty);

      final measurements = HevyMeasurementImportResult.fromJson({'measurements_created': 12});
      expect(measurements.measurementsCreated, 12);
    });
  });
}

void _completedTests() {
  group('ActivitySet.completed', () {
    test('an older server\'s set without the flag counts as done', () {
      final set = ActivitySet.fromJson({'id': 1, 'position': 0, 'set_type': 'normal'});
      expect(set.completed, isTrue);
    });

    test('is sent to the server, and survives copyWith', () {
      const set = ActivitySet(reps: 5, completed: false);
      expect(set.toJson()['completed'], false);
      expect(set.copyWith(reps: 6).completed, isFalse);
      expect(set.copyWith(completed: true).completed, isTrue);
    });

    test('an exercise lists only its completed sets', () {
      const exercise = ActivityExercise(
        exerciseId: 1,
        sets: [ActivitySet(reps: 5), ActivitySet(reps: 6, completed: false)],
      );
      expect(exercise.completedSets.map((s) => s.reps), [5]);
    });
  });
}
