import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/equipment.dart';
import '../../models/exercise.dart';
import '../../models/exercise_tutorial.dart';
import '../../models/muscle_group.dart';
import 'exercises_repository.dart';

final exerciseSearchProvider = StateProvider<String>((ref) => '');

/// The *whole* catalog, unfiltered and unpaged -- only for the routine/
/// activity exercise pickers, which build an in-memory menu/lookup and need
/// every row up front. The exercises list screen itself uses
/// [exercisePagingProvider] instead; the two never share a provider because
/// paging that one out from under the pickers would leave them with only a
/// partial catalog to search and pick from.
final exerciseListProvider = FutureProvider.autoDispose<List<Exercise>>((ref) {
  final search = ref.watch(exerciseSearchProvider);
  return ref.watch(exercisesRepositoryProvider).list(search: search);
});

const exercisePageSize = 40;

class ExercisePageState {
  const ExercisePageState({
    this.items = const [],
    this.total = 0,
    this.hasMore = true,
    this.loading = true,
    this.loadingMore = false,
    this.error,
    this.search = '',
  });

  final List<Exercise> items;
  final int total;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final Object? error;
  final String search;

  ExercisePageState copyWith({
    List<Exercise>? items,
    int? total,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
    String? search,
  }) {
    return ExercisePageState(
      items: items ?? this.items,
      total: total ?? this.total,
      hasMore: hasMore ?? this.hasMore,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
      search: search ?? this.search,
    );
  }
}

/// Pages the exercises list screen through the catalog instead of fetching
/// it all at once, and debounces the search box so each keystroke doesn't
/// fire its own request.
class ExercisePagingNotifier extends StateNotifier<ExercisePageState> {
  ExercisePagingNotifier(this._repository) : super(const ExercisePageState()) {
    unawaited(_load(reset: true));
  }

  final ExercisesRepository _repository;
  Timer? _debounce;
  int _requestId = 0;

  void setSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (value == state.search) return;
      state = state.copyWith(search: value);
      unawaited(_load(reset: true));
    });
  }

  Future<void> loadMore() {
    if (state.loading || state.loadingMore || !state.hasMore) {
      return Future.value();
    }
    return _load(reset: false);
  }

  Future<void> refresh() => _load(reset: true);

  Future<void> _load({required bool reset}) async {
    final requestId = ++_requestId;
    state = state.copyWith(loading: reset, loadingMore: !reset, clearError: true);
    try {
      final page = await _repository.listPage(
        search: state.search,
        limit: exercisePageSize,
        offset: reset ? 0 : state.items.length,
      );
      if (requestId != _requestId) {
        return; // superseded by a newer search/refresh
      }
      final items = reset ? page.items : [...state.items, ...page.items];
      state = state.copyWith(
        items: items,
        total: page.total,
        hasMore: items.length < page.total,
        loading: false,
        loadingMore: false,
      );
    } catch (error) {
      if (requestId != _requestId) return;
      state = state.copyWith(loading: false, loadingMore: false, error: error);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final exercisePagingProvider =
    StateNotifierProvider.autoDispose<ExercisePagingNotifier, ExercisePageState>((ref) {
      return ExercisePagingNotifier(ref.watch(exercisesRepositoryProvider));
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

/// Exercises that train a given muscle (primary or secondary) -- backs the
/// modal an activity's muscle chips open (see `ExerciseFilterSheet`).
final exercisesByMuscleProvider = FutureProvider.autoDispose.family<List<Exercise>, MuscleGroup>((
  ref,
  muscle,
) {
  return ref.watch(exercisesRepositoryProvider).list(muscle: muscle);
});

/// Exercises performed with a given piece of equipment -- backs the modal
/// an activity's equipment chip opens (see `ExerciseFilterSheet`).
final exercisesByEquipmentProvider = FutureProvider.autoDispose.family<List<Exercise>, Equipment>((
  ref,
  equipment,
) {
  return ref.watch(exercisesRepositoryProvider).list(equipment: equipment);
});
