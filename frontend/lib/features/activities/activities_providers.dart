import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/activity.dart';
import 'activities_repository.dart';

final activityListProvider = FutureProvider.autoDispose<List<Activity>>((ref) {
  return ref.watch(activitiesRepositoryProvider).list();
});

final activityProvider = FutureProvider.autoDispose.family<Activity, int>((ref, id) {
  return ref.watch(activitiesRepositoryProvider).get(id);
});

/// How many logged activities each exercise (by id) appears in -- what the
/// exercise picker ranks its results by. Empty while loading or if the
/// history can't be fetched, so the picker never waits on or fails because
/// of it.
final exerciseUsageProvider = FutureProvider.autoDispose<Map<int, int>>((ref) async {
  final activities = await ref.watch(activityListProvider.future);
  final counts = <int, int>{};
  for (final activity in activities) {
    for (final id in {for (final e in activity.exercises) e.exerciseId}) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
  }
  return counts;
});
