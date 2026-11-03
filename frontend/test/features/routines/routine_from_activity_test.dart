import 'package:dinatos_frontend/features/routines/routine_from_activity.dart';
import 'package:dinatos_frontend/models/activity.dart';
import 'package:dinatos_frontend/models/set_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('routineFromActivity', () {
    test('turns ticked sets into targets and keeps notes and supersets', () {
      final routine = routineFromActivity('Push day', [
        const ActivityExercise(
          exerciseId: 3,
          supersetGroup: 1,
          notes: 'slow negatives',
          sets: [
            ActivitySet(
              setType: SetType.warmup,
              weightKg: 40,
              reps: 10,
              durationSeconds: 30,
              completed: true,
            ),
            ActivitySet(weightKg: 60, reps: 8, distanceKm: 1.5, completed: true),
          ],
        ),
      ]);

      expect(routine.name, 'Push day');
      final exercise = routine.exercises.single;
      expect(exercise.exerciseId, 3);
      expect(exercise.supersetGroup, 1);
      expect(exercise.notes, 'slow negatives');
      expect(exercise.sets, hasLength(2));
      expect(exercise.sets[0].setType, SetType.warmup);
      expect(exercise.sets[0].targetWeightKg, 40);
      expect(exercise.sets[0].targetReps, 10);
      expect(exercise.sets[0].targetDurationSeconds, 30);
      expect(exercise.sets[1].targetDistanceKm, 1.5);
    });

    test('drops sets never ticked, and exercises left with none', () {
      final routine = routineFromActivity('Legs', [
        const ActivityExercise(
          exerciseId: 1,
          sets: [ActivitySet(reps: 5), ActivitySet(reps: 5, completed: false)],
        ),
        const ActivityExercise(exerciseId: 2, sets: [ActivitySet(reps: 5, completed: false)]),
      ]);

      expect(routine.exercises, hasLength(1));
      expect(routine.exercises.single.sets, hasLength(1));
    });
  });
}
