import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/routine.dart';
import 'routines_repository.dart';

final routineListProvider = FutureProvider.autoDispose<List<Routine>>((ref) {
  return ref.watch(routinesRepositoryProvider).list();
});

final routineProvider = FutureProvider.autoDispose.family<Routine, int>((ref, id) {
  return ref.watch(routinesRepositoryProvider).get(id);
});
