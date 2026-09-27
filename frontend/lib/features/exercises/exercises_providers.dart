import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/exercise.dart';
import '../../models/exercise_tutorial.dart';
import 'exercises_repository.dart';

final exerciseSearchProvider = StateProvider<String>((ref) => '');

final exerciseListProvider = FutureProvider.autoDispose<List<Exercise>>((ref) {
  final search = ref.watch(exerciseSearchProvider);
  return ref.watch(exercisesRepositoryProvider).list(search: search);
});

final exerciseProvider = FutureProvider.autoDispose.family<Exercise, int>((ref, id) {
  return ref.watch(exercisesRepositoryProvider).get(id);
});

final exerciseTutorialProvider = FutureProvider.autoDispose.family<ExerciseTutorial?, int>((
  ref,
  id,
) {
  return ref.watch(exercisesRepositoryProvider).getTutorial(id);
});
