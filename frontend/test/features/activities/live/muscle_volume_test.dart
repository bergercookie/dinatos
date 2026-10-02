import 'package:dinatos_frontend/features/activities/live/muscle_volume.dart';
import 'package:dinatos_frontend/models/activity.dart';
import 'package:dinatos_frontend/models/exercise.dart';
import 'package:dinatos_frontend/models/muscle_group.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeMuscleVolumes', () {
    test('credits a primary muscle in full and a secondary muscle at half weight', () {
      final catalog = [
        const Exercise(
          id: 1,
          name: 'Bench Press',
          primaryMuscles: [MuscleGroup.chest],
          secondaryMuscles: [MuscleGroup.triceps],
        ),
      ];
      final exercises = [
        const ActivityExercise(exerciseId: 1, sets: [ActivitySet(weightKg: 100, reps: 5)]),
      ];

      final volumes = computeMuscleVolumes(exercises, catalog);

      expect(volumes[MuscleGroup.chest], 500);
      expect(volumes[MuscleGroup.triceps], 250);
    });

    test('accumulates volume across multiple sets and exercises sharing a muscle', () {
      final catalog = [
        const Exercise(id: 1, name: 'Bench Press', primaryMuscles: [MuscleGroup.chest]),
        const Exercise(id: 2, name: 'Cable Fly', primaryMuscles: [MuscleGroup.chest]),
      ];
      final exercises = [
        const ActivityExercise(
          exerciseId: 1,
          sets: [ActivitySet(weightKg: 100, reps: 5), ActivitySet(weightKg: 80, reps: 8)],
        ),
        const ActivityExercise(exerciseId: 2, sets: [ActivitySet(weightKg: 20, reps: 12)]),
      ];

      final volumes = computeMuscleVolumes(exercises, catalog);

      expect(volumes[MuscleGroup.chest], 500 + 640 + 240);
    });

    test('falls back to rep count alone for a set with no weight tracked', () {
      final catalog = [
        const Exercise(id: 1, name: 'Pull-up', primaryMuscles: [MuscleGroup.lats]),
      ];
      final exercises = [
        const ActivityExercise(exerciseId: 1, sets: [ActivitySet(reps: 10)]),
      ];

      final volumes = computeMuscleVolumes(exercises, catalog);

      expect(volumes[MuscleGroup.lats], 10);
    });

    test('ignores a set with no reps logged yet', () {
      final catalog = [
        const Exercise(id: 1, name: 'Squat', primaryMuscles: [MuscleGroup.quadriceps]),
      ];
      final exercises = [
        const ActivityExercise(exerciseId: 1, sets: [ActivitySet(weightKg: 60)]),
      ];

      expect(computeMuscleVolumes(exercises, catalog), isEmpty);
    });

    test('ignores an exercise id missing from the catalog instead of throwing', () {
      final exercises = [
        const ActivityExercise(exerciseId: 999, sets: [ActivitySet(weightKg: 60, reps: 5)]),
      ];

      expect(computeMuscleVolumes(exercises, const []), isEmpty);
    });

    test('returns nothing for an empty session', () {
      expect(computeMuscleVolumes(const [], const []), isEmpty);
    });
  });
}
