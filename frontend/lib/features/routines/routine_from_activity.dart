import '../../models/activity.dart';
import '../../models/routine.dart';

/// A routine named [name] built from what was actually done in [exercises]:
/// each ticked set's weight, reps, distance and duration become that set's
/// targets, so the routine replays the workout. Sets never ticked are left
/// out, and so are exercises with none -- a routine is a plan of work done.
Routine routineFromActivity(String name, List<ActivityExercise> exercises) {
  return Routine(
    name: name,
    exercises: [
      for (final exercise in exercises)
        if (exercise.completedSets.isNotEmpty)
          RoutineExercise(
            exerciseId: exercise.exerciseId,
            supersetGroup: exercise.supersetGroup,
            notes: exercise.notes,
            sets: [
              for (final set in exercise.completedSets)
                RoutineSet(
                  setType: set.setType,
                  targetWeightKg: set.weightKg,
                  targetReps: set.reps,
                  targetDistanceKm: set.distanceKm,
                  targetDurationSeconds: set.durationSeconds,
                ),
            ],
          ),
    ],
  );
}
