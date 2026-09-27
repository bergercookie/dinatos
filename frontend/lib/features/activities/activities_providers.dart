import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/activity.dart';
import 'activities_repository.dart';

final activityListProvider = FutureProvider.autoDispose<List<Activity>>((ref) {
  return ref.watch(activitiesRepositoryProvider).list();
});

final activityProvider = FutureProvider.autoDispose.family<Activity, int>((ref, id) {
  return ref.watch(activitiesRepositoryProvider).get(id);
});
