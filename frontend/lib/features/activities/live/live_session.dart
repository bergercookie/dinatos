import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_notifier.dart';
import '../../../core/auth/auth_state.dart';
import '../../../models/activity.dart';
import '../../../models/routine.dart';
import '../../../models/superset.dart';
import '../../../models/uid.dart';
import 'live_session_storage.dart';

/// An in-progress (or just-finished, not yet saved) live workout -- built up
/// one exercise/set at a time as they're actually performed, in contrast to
/// [ActivityFormScreen]'s whole-activity-then-submit flow. `endedAt` is only
/// set once the person taps "Finish workout"; the session is still held
/// (for the summary screen to read) until it's either saved or discarded.
class LiveActivitySession {
  const LiveActivitySession({
    required this.startedAt,
    this.endedAt,
    this.exercises = const [],
    DateTime? clockOrigin,
    this.pausedAt,
    this.savedActivityId,
    this.savedTitle,
    this.pendingTitle,
    this.routineId,
    this.routineName,
  }) : clockOrigin = clockOrigin ?? startedAt;

  /// When the workout actually began -- what gets saved as the activity's
  /// `started_at`. Never moved by the on-screen stopwatch controls.
  final DateTime startedAt;

  /// The on-screen stopwatch's own zero point: elapsed time is
  /// `(pausedAt ?? now) - clockOrigin`. Starts equal to [startedAt]; resetting,
  /// setting or resuming the stopwatch shifts it, so the display can be
  /// adjusted without rewriting when the workout really started.
  final DateTime clockOrigin;

  /// Non-null while the stopwatch is paused (frozen at this instant).
  final DateTime? pausedAt;

  bool get isPaused => pausedAt != null;

  /// What the stopwatch reads at [now].
  Duration clockElapsedAt(DateTime now) {
    final elapsed = (pausedAt ?? now).difference(clockOrigin);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  final DateTime? endedAt;
  final List<ActivityExercise> exercises;

  /// The saved routine this workout was started from, if any: saved onto the
  /// activity as `routine_id`, and its name is the summary's default title.
  final int? routineId;
  final String? routineName;

  /// Non-null once `POST /activities` has actually succeeded for this
  /// session -- tracked on the session itself, not as local screen state,
  /// so the summary screen can't be reached again (a browser back button, a
  /// restart right after saving) still showing an enabled "Save workout"
  /// and double-posting the same workout as a second activity. Cleared only
  /// by [LiveActivityNotifier.discard], same as everything else here.
  final int? savedActivityId;
  final String? savedTitle;

  bool get isSaved => savedActivityId != null;

  /// Non-null after a save attempt that got no HTTP response at all (a dropped
  /// connection, a timeout): the server may or may not have stored the
  /// workout, so the retry must send exactly what the first attempt did. The
  /// backend treats a request with the same title, start and end as the same
  /// save replayed -- which only works if the title is not edited in between.
  /// Persisted with the session, so it survives the app being killed.
  final String? pendingTitle;

  /// How many sets have been completed (ticked off) so far, across every
  /// exercise.
  int get totalSets =>
      exercises.fold<int>(0, (sum, exercise) => sum + exercise.completedSets.length);

  /// Sum of reps across every set logged so far, regardless of weight --
  /// distinct from [totalVolumeKg], which is zero for a set with no weight
  /// tracked (e.g. bodyweight work) even though real reps were done.
  int get totalReps => exercises.fold<int>(
    0,
    (sum, exercise) =>
        sum + exercise.completedSets.fold<int>(0, (setSum, set) => setSum + (set.reps ?? 0)),
  );

  /// Sum of weight x reps across every set logged so far -- sets missing
  /// either value (an exercise that doesn't track one, or one not filled in
  /// yet) contribute 0, same convention `_subtitle`-style summaries elsewhere
  /// use for an unset field.
  double get totalVolumeKg => exercises.fold<double>(
    0,
    (sum, exercise) =>
        sum +
        exercise.completedSets.fold<double>(0, (setSum, set) {
          final weight = set.weightKg;
          final reps = set.reps;
          if (weight == null || reps == null) return setSum;
          return setSum + weight * reps;
        }),
  );

  LiveActivitySession copyWith({
    DateTime? endedAt,
    List<ActivityExercise>? exercises,
    DateTime? clockOrigin,
    DateTime? pausedAt,
    bool clearPausedAt = false,
    int? savedActivityId,
    String? savedTitle,
    String? pendingTitle,
    bool clearPendingTitle = false,
  }) => LiveActivitySession(
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    exercises: exercises ?? this.exercises,
    clockOrigin: clockOrigin ?? this.clockOrigin,
    pausedAt: clearPausedAt ? null : (pausedAt ?? this.pausedAt),
    savedActivityId: savedActivityId ?? this.savedActivityId,
    savedTitle: savedTitle ?? this.savedTitle,
    pendingTitle: clearPendingTitle ? null : (pendingTitle ?? this.pendingTitle),
    routineId: routineId,
    routineName: routineName,
  );
}

class LiveActivityNotifier extends StateNotifier<LiveActivitySession?> {
  /// [restored] seeds the session found on disk at startup; every later change
  /// is written back through [storage] so it survives the app being killed.
  LiveActivityNotifier({
    PersistedLiveSession? restored,
    this._storage = const NoopLiveSessionStorage(),
    this._currentUserId,
  }) : ownerId = restored?.ownerId,
       super(restored?.session) {
    addListener(
      (session) => _storage.write(
        session == null ? null : PersistedLiveSession(session: session, ownerId: ownerId),
      ),
      fireImmediately: false,
    );
  }

  final LiveSessionStorage _storage;
  final int? Function()? _currentUserId;

  /// The account the session belongs to (null if it started before login state was known).
  int? ownerId;

  void start() {
    ownerId = _currentUserId?.call();
    state = LiveActivitySession(startedAt: DateTime.now());
  }

  /// Starts a workout pre-filled from [routine]: its exercises, notes and
  /// target sets (weight/reps), to be edited into what was actually done --
  /// the same copy `ActivityFormScreen`'s "Start from a saved routine" makes.
  void startFromRoutine(Routine routine) {
    ownerId = _currentUserId?.call();
    state = LiveActivitySession(
      startedAt: DateTime.now(),
      routineId: routine.id,
      routineName: routine.name,
      exercises: [
        for (final exercise in routine.exercises)
          ActivityExercise(
            uid: nextUid(),
            exerciseId: exercise.exerciseId,
            supersetGroup: exercise.supersetGroup,
            notes: exercise.notes,
            sets: [
              for (final set in exercise.sets)
                ActivitySet(
                  uid: nextUid(),
                  setType: set.setType,
                  weightKg: set.targetWeightKg,
                  reps: set.targetReps,
                  distanceKm: set.targetDistanceKm,
                  durationSeconds: set.targetDurationSeconds,
                  completed: false,
                ),
            ],
          ),
      ],
    );
  }

  void addExercise(int exerciseId) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      exercises: [
        ...current.exercises,
        ActivityExercise(uid: nextUid(), exerciseId: exerciseId),
      ],
    );
  }

  /// Appends several exercises at once, in order, each with no sets yet.
  void addExercises(List<int> exerciseIds) {
    final current = state;
    if (current == null || exerciseIds.isEmpty) return;
    state = current.copyWith(
      exercises: [
        ...current.exercises,
        for (final id in exerciseIds) ActivityExercise(uid: nextUid(), exerciseId: id),
      ],
    );
  }

  void removeExerciseAt(int index) =>
      _editExercises((e) => removeItem(e, index, activitySupersets));

  /// Puts the exercise at [index] and the next one in one superset.
  void linkExerciseWithNext(int index) =>
      _editExercises((e) => linkWithNext(e, index, activitySupersets));

  /// Takes the exercise at [index] out of its superset.
  void unlinkExercise(int index) => _editExercises((e) => unlink(e, index, activitySupersets));

  /// Moves the exercise at [from] to [to].
  void moveExercise(int from, int to) =>
      _editExercises((e) => moveItem(e, from, to, activitySupersets));

  void _editExercises(List<ActivityExercise> Function(List<ActivityExercise>) edit) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(exercises: edit(current.exercises));
  }

  void updateExerciseAt(int index, ActivityExercise updated) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(exercises: List.of(current.exercises)..[index] = updated);
  }

  /// Freezes the stopwatch at its current reading.
  void pauseClock() {
    final current = state;
    if (current == null || current.isPaused) return;
    state = current.copyWith(pausedAt: DateTime.now());
  }

  /// Un-freezes the stopwatch, continuing from where it was paused.
  void resumeClock() {
    final current = state;
    final pausedAt = current?.pausedAt;
    if (current == null || pausedAt == null) return;
    state = current.copyWith(
      clockOrigin: current.clockOrigin.add(DateTime.now().difference(pausedAt)),
      clearPausedAt: true,
    );
  }

  /// Zeroes the stopwatch and (re)starts it counting up.
  void resetClock() => setClock(Duration.zero);

  /// Sets the stopwatch to read [elapsed] right now and (re)starts it
  /// counting up from there -- also un-pausing it.
  void setClock(Duration elapsed) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(clockOrigin: DateTime.now().subtract(elapsed), clearPausedAt: true);
  }

  void finish() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(endedAt: DateTime.now());
  }

  /// Records that this session was actually saved as activity [activityId]
  /// -- see [LiveActivitySession.savedActivityId].
  void markSaved({required int activityId, required String title}) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      savedActivityId: activityId,
      savedTitle: title,
      clearPendingTitle: true,
    );
  }

  /// Records that a save attempt under [title] may have reached the server --
  /// see [LiveActivitySession.pendingTitle].
  void markSaveUncertain(String title) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(pendingTitle: title);
  }

  /// The server definitely did not store the workout (it answered with an
  /// error), so the title is free to change again.
  void clearSaveUncertainty() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(clearPendingTitle: true);
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
  int? userId() {
    final auth = ref.read(authNotifierProvider);
    return auth is AuthAuthenticated ? auth.user.id : null;
  }

  final notifier = LiveActivityNotifier(
    restored: ref.watch(restoredLiveSessionProvider),
    storage: ref.watch(liveSessionStorageProvider),
    currentUserId: userId,
  );
  // A workout restored from disk belongs to whoever started it: drop it if a
  // different account signs in. (A mere session expiry keeps it -- the same
  // person logs back in and carries on.)
  ref.listen<AuthState>(authNotifierProvider, (_, next) {
    if (next is AuthAuthenticated && notifier.ownerId != null && notifier.ownerId != next.user.id) {
      notifier.discard();
    }
  });
  return notifier;
});

/// What `main()` found on disk at startup; overridden there.
final restoredLiveSessionProvider = Provider<PersistedLiveSession?>((ref) => null);

final liveSessionStorageProvider = Provider<LiveSessionStorage>(
  (ref) => const NoopLiveSessionStorage(),
);
