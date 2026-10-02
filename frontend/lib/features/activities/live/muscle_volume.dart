import '../../../models/activity.dart';
import '../../../models/exercise.dart';
import '../../../models/muscle_group.dart';

/// How much a set's volume (weight x reps, or just rep count when no weight
/// is tracked) counts toward a *secondary* muscle, relative to a primary
/// one -- a common convention (e.g. Hevy, Strong) for "worked, but not the
/// main target".
const secondaryMuscleWeight = 0.5;

/// Accumulated per-muscle volume across every set logged in a live session
/// so far, for the muscle-emphasis radar chart: each set's weight x reps
/// (or, for a bodyweight/no-weight set, just its rep count) is credited in
/// full to every muscle the exercise lists as primary, and at
/// [secondaryMuscleWeight] to every muscle it lists as secondary. An
/// exercise missing from [catalog] (shouldn't normally happen -- it would
/// mean the picker offered an id the catalog no longer has) contributes
/// nothing rather than throwing.
Map<MuscleGroup, double> computeMuscleVolumes(
  List<ActivityExercise> exercises,
  List<Exercise> catalog,
) {
  final catalogById = {for (final exercise in catalog) exercise.id: exercise};
  final volumes = <MuscleGroup, double>{};

  for (final activityExercise in exercises) {
    final exercise = catalogById[activityExercise.exerciseId];
    if (exercise == null) continue;

    for (final set in activityExercise.sets) {
      final reps = set.reps;
      if (reps == null || reps <= 0) continue;
      final setVolume = (set.weightKg ?? 0) > 0 ? set.weightKg! * reps : reps.toDouble();

      for (final muscle in exercise.primaryMuscles) {
        volumes[muscle] = (volumes[muscle] ?? 0) + setVolume;
      }
      for (final muscle in exercise.secondaryMuscles) {
        volumes[muscle] = (volumes[muscle] ?? 0) + setVolume * secondaryMuscleWeight;
      }
    }
  }

  return volumes;
}
