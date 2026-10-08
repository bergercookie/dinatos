import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/planned_workout.dart';
import 'planned_workouts_repository.dart';

/// Every planned workout, soonest first. Small by nature (one entry per
/// scheduled session), so fetched whole rather than per month.
final plannedWorkoutListProvider = FutureProvider.autoDispose<List<PlannedWorkout>>((ref) {
  return ref.watch(plannedWorkoutsRepositoryProvider).list();
});

final plannedWorkoutProvider = FutureProvider.autoDispose.family<PlannedWorkout, int>((ref, id) {
  return ref.watch(plannedWorkoutsRepositoryProvider).get(id);
});

final calendarFeedProvider = FutureProvider.autoDispose<CalendarFeed>((ref) {
  return ref.watch(plannedWorkoutsRepositoryProvider).feed();
});
