import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/workout.dart';
import 'workouts_repository.dart';

final workoutListProvider = FutureProvider.autoDispose<List<Workout>>((ref) {
  return ref.watch(workoutsRepositoryProvider).list();
});

final workoutProvider = FutureProvider.autoDispose.family<Workout, int>((ref, id) {
  return ref.watch(workoutsRepositoryProvider).get(id);
});
