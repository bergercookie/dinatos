import 'package:dinatos_frontend/features/activities/live/live_session.dart';
import 'package:dinatos_frontend/models/activity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LiveActivityNotifier', () {
    test('starts with no session until start() is called', () {
      final notifier = LiveActivityNotifier();
      expect(notifier.state, isNull);
    });

    test('start() opens a session timestamped now, with no exercises yet', () {
      final notifier = LiveActivityNotifier();

      notifier.start();

      expect(notifier.state, isNotNull);
      expect(notifier.state!.exercises, isEmpty);
      expect(notifier.state!.endedAt, isNull);
      expect(
        notifier.state!.startedAt.difference(DateTime.now()).abs(),
        lessThan(const Duration(seconds: 5)),
      );
    });

    test('addExercise/updateExerciseAt/removeExerciseAt build up and edit the exercise list', () {
      final notifier = LiveActivityNotifier()..start();

      notifier.addExercise(1);
      notifier.addExercise(2);
      expect(notifier.state!.exercises.map((e) => e.exerciseId), [1, 2]);

      notifier.updateExerciseAt(
        0,
        const ActivityExercise(exerciseId: 1, sets: [ActivitySet(weightKg: 50, reps: 10)]),
      );
      expect(notifier.state!.exercises[0].sets, hasLength(1));

      notifier.removeExerciseAt(1);
      expect(notifier.state!.exercises.map((e) => e.exerciseId), [1]);
    });

    test('mutating methods are a no-op before start()', () {
      final notifier = LiveActivityNotifier();

      notifier.addExercise(1);

      expect(notifier.state, isNull);
    });

    test('finish() stamps endedAt without touching logged exercises', () {
      final notifier = LiveActivityNotifier()..start();
      notifier.addExercise(1);

      notifier.finish();

      expect(notifier.state!.endedAt, isNotNull);
      expect(notifier.state!.exercises, hasLength(1));
    });

    test('discard() clears the session back to null', () {
      final notifier = LiveActivityNotifier()..start();

      notifier.discard();

      expect(notifier.state, isNull);
    });
  });

  group('markSaved', () {
    test('records the saved activity id/title and flips isSaved', () {
      final notifier = LiveActivityNotifier()..start();

      expect(notifier.state!.isSaved, isFalse);
      notifier.markSaved(activityId: 42, title: 'Leg day');

      expect(notifier.state!.isSaved, isTrue);
      expect(notifier.state!.savedActivityId, 42);
      expect(notifier.state!.savedTitle, 'Leg day');
    });

    test('is a no-op before start()', () {
      final notifier = LiveActivityNotifier();

      notifier.markSaved(activityId: 42, title: 'Leg day');

      expect(notifier.state, isNull);
    });
  });

  test('totalSets counts every set across all exercises', () {
    final session = LiveActivitySession(
      startedAt: DateTime(2026),
      exercises: const [
        ActivityExercise(exerciseId: 1, sets: [ActivitySet(reps: 5), ActivitySet(reps: 5)]),
        ActivityExercise(exerciseId: 2, sets: [ActivitySet(reps: 8)]),
        ActivityExercise(exerciseId: 3),
      ],
    );

    expect(session.totalSets, 3);
    expect(LiveActivitySession(startedAt: DateTime(2026)).totalSets, 0);
  });

  group('LiveActivitySession.totalVolumeKg', () {
    test('sums weight x reps across every set, skipping any with a value missing', () {
      final session = LiveActivitySession(
        startedAt: DateTime(2026),
        exercises: const [
          ActivityExercise(
            exerciseId: 1,
            sets: [
              ActivitySet(weightKg: 100, reps: 5),
              ActivitySet(weightKg: 80, reps: 8),
              ActivitySet(reps: 10),
              ActivitySet(weightKg: 20),
            ],
          ),
        ],
      );

      expect(session.totalVolumeKg, 500 + 640);
    });

    test('is zero for a session with no sets logged yet', () {
      final session = LiveActivitySession(startedAt: DateTime(2026));
      expect(session.totalVolumeKg, 0);
    });
  });

  group('LiveActivitySession.totalReps', () {
    test('sums reps across every set, counting a set with no weight too', () {
      final session = LiveActivitySession(
        startedAt: DateTime(2026),
        exercises: const [
          ActivityExercise(
            exerciseId: 1,
            sets: [
              ActivitySet(weightKg: 100, reps: 5),
              ActivitySet(reps: 12),
              ActivitySet(weightKg: 20),
            ],
          ),
        ],
      );

      expect(session.totalReps, 5 + 12);
    });

    test('is zero for a session with no sets logged yet', () {
      expect(LiveActivitySession(startedAt: DateTime(2026)).totalReps, 0);
    });
  });

  group('stopwatch', () {
    test('setClock() sets the reading and runs; pauseClock/resumeClock freeze and continue', () {
      final notifier = LiveActivityNotifier()..start();

      notifier.setClock(const Duration(minutes: 10));
      var clock = notifier.state!.clockElapsedAt(DateTime.now());
      expect(clock, greaterThanOrEqualTo(const Duration(minutes: 10)));
      expect(clock, lessThan(const Duration(minutes: 10, seconds: 5)));
      expect(notifier.state!.isPaused, isFalse);

      notifier.pauseClock();
      expect(notifier.state!.isPaused, isTrue);
      final frozen = notifier.state!.clockElapsedAt(DateTime.now().add(const Duration(hours: 1)));
      expect(frozen, lessThan(const Duration(minutes: 10, seconds: 5)));

      notifier.resumeClock();
      expect(notifier.state!.isPaused, isFalse);
      clock = notifier.state!.clockElapsedAt(DateTime.now());
      expect(clock, lessThan(const Duration(minutes: 10, seconds: 5)));
    });

    test('resetClock() zeroes and un-pauses, without moving startedAt', () {
      final notifier = LiveActivityNotifier()..start();
      final startedAt = notifier.state!.startedAt;
      notifier.setClock(const Duration(minutes: 30));
      notifier.pauseClock();

      notifier.resetClock();

      expect(notifier.state!.isPaused, isFalse);
      expect(notifier.state!.clockElapsedAt(DateTime.now()), lessThan(const Duration(seconds: 5)));
      expect(notifier.state!.startedAt, startedAt);
    });

    test('setClock() while paused resumes counting', () {
      final notifier = LiveActivityNotifier()..start();
      notifier.pauseClock();
      notifier.setClock(const Duration(minutes: 1));
      expect(notifier.state!.isPaused, isFalse);
    });
  });
}
