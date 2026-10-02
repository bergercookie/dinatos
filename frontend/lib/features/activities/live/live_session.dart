import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/activity.dart';

/// An in-progress (or just-finished, not yet saved) live workout -- built up
/// one exercise/set at a time as they're actually performed, in contrast to
/// [ActivityFormScreen]'s whole-activity-then-submit flow. `endedAt` is only
/// set once the person taps "Finish workout"; the session is still held
/// (for the summary screen to read) until it's either saved or discarded.
class LiveActivitySession {
  const LiveActivitySession({required this.startedAt, this.endedAt, this.exercises = const []});

  final DateTime startedAt;
  final DateTime? endedAt;
  final List<ActivityExercise> exercises;

  /// How many sets have been logged so far, across every exercise -- sets are
  /// added as they're performed, so each one counts as completed.
  int get totalSets => exercises.fold<int>(0, (sum, exercise) => sum + exercise.sets.length);

  /// Sum of weight x reps across every set logged so far -- sets missing
  /// either value (an exercise that doesn't track one, or one not filled in
  /// yet) contribute 0, same convention `_subtitle`-style summaries elsewhere
  /// use for an unset field.
  double get totalVolumeKg => exercises.fold<double>(
    0,
    (sum, exercise) =>
        sum +
        exercise.sets.fold<double>(0, (setSum, set) {
          final weight = set.weightKg;
          final reps = set.reps;
          if (weight == null || reps == null) return setSum;
          return setSum + weight * reps;
        }),
  );

  LiveActivitySession copyWith({DateTime? endedAt, List<ActivityExercise>? exercises}) =>
      LiveActivitySession(
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        exercises: exercises ?? this.exercises,
      );
}

class LiveActivityNotifier extends StateNotifier<LiveActivitySession?> {
  LiveActivityNotifier() : super(null);

  void start() => state = LiveActivitySession(startedAt: DateTime.now());

  void addExercise(int exerciseId) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      exercises: [
        ...current.exercises,
        ActivityExercise(exerciseId: exerciseId),
      ],
    );
  }

  void removeExerciseAt(int index) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(exercises: List.of(current.exercises)..removeAt(index));
  }

  void updateExerciseAt(int index, ActivityExercise updated) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(exercises: List.of(current.exercises)..[index] = updated);
  }

  void finish() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(endedAt: DateTime.now());
  }

  /// Clears the session -- after it's been saved, or if the person backs out
  /// without saving. Not `autoDispose`'d on the provider itself (the session
  /// must survive switching tabs mid-workout), so this is the only way back
  /// to "no active session".
  void discard() => state = null;
}

/// `null` means no live workout is currently in progress. Deliberately not
/// `autoDispose`: a `StatefulShellRoute` branch switch (see `core/router.dart`)
/// disposes nothing about this provider's watchers, but the session itself
/// must keep counting time and holding logged sets even while the person is
/// looking at a different tab.
final liveActivityProvider = StateNotifierProvider<LiveActivityNotifier, LiveActivitySession?>((
  ref,
) {
  return LiveActivityNotifier();
});
