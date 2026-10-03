import 'package:dinatos_frontend/features/activities/live/live_session.dart';
import 'package:dinatos_frontend/models/activity.dart';
import 'package:dinatos_frontend/models/routine.dart';
import 'package:dinatos_frontend/models/set_type.dart';
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

    test('startFromRoutine() pre-fills exercises, notes and target sets from the routine', () {
      final notifier = LiveActivityNotifier();

      notifier.startFromRoutine(
        const Routine(
          id: 7,
          name: 'Push day',
          exercises: [
            RoutineExercise(
              exerciseId: 3,
              notes: 'slow negatives',
              sets: [
                RoutineSet(setType: SetType.warmup, targetWeightKg: 40, targetReps: 12),
                RoutineSet(targetWeightKg: 80, targetReps: 5),
              ],
            ),
            RoutineExercise(exerciseId: 9),
          ],
        ),
      );

      final session = notifier.state!;
      expect(session.routineId, 7);
      expect(session.routineName, 'Push day');
      expect(session.endedAt, isNull);
      expect(session.exercises.map((e) => e.exerciseId), [3, 9]);
      expect(session.exercises[0].notes, 'slow negatives');
      expect(session.exercises[0].sets.map((s) => s.setType), [SetType.warmup, SetType.normal]);
      expect(session.exercises[0].sets.map((s) => s.weightKg), [40, 80]);
      expect(session.exercises[0].sets.map((s) => s.reps), [12, 5]);
      expect(session.exercises[1].sets, isEmpty);
    });

    test('editing a workout started from a routine keeps its routine link', () {
      final notifier = LiveActivityNotifier()
        ..startFromRoutine(const Routine(id: 7, name: 'Push day'));

      notifier.addExercise(1);

      expect(notifier.state!.routineId, 7);
      expect(notifier.state!.routineName, 'Push day');
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

    group('supersets', () {
      LiveActivityNotifier withExercises(int count) {
        final notifier = LiveActivityNotifier()..start();
        for (var i = 1; i <= count; i++) {
          notifier.addExercise(i);
        }
        return notifier;
      }

      List<int?> groups(LiveActivityNotifier n) =>
          n.state!.exercises.map((e) => e.supersetGroup).toList();
      List<int> order(LiveActivityNotifier n) =>
          n.state!.exercises.map((e) => e.exerciseId).toList();

      test('linking, unlinking and moving keep groups as runs of neighbours', () {
        final notifier = withExercises(4);

        notifier.linkExerciseWithNext(1);
        expect(groups(notifier), [null, 1, 1, null]);

        notifier.linkExerciseWithNext(2);
        expect(groups(notifier), [null, 1, 1, 1]);

        notifier.moveExercise(3, 0);
        expect(order(notifier), [4, 1, 2, 3]);
        // Exercise 4 left the run it was in, and a lone neighbour is no superset.
        expect(groups(notifier), [null, null, 1, 1]);

        notifier.unlinkExercise(2);
        expect(groups(notifier), [null, null, null, null]);
      });

      test('removing one of a pair leaves the other alone', () {
        final notifier = withExercises(3)..linkExerciseWithNext(0);
        expect(groups(notifier), [1, 1, null]);

        notifier.removeExerciseAt(1);

        expect(order(notifier), [1, 3]);
        expect(groups(notifier), [null, null]);
      });

      test('a routine superset starts the workout as one', () {
        final notifier = LiveActivityNotifier()
          ..startFromRoutine(
            const Routine(
              name: 'Upper',
              exercises: [
                RoutineExercise(exerciseId: 1, supersetGroup: 5),
                RoutineExercise(exerciseId: 2, supersetGroup: 5),
                RoutineExercise(exerciseId: 3),
              ],
            ),
          );

        expect(groups(notifier), [5, 5, null]);
      });

      test('they do nothing with no workout under way', () {
        final notifier = LiveActivityNotifier();

        notifier.linkExerciseWithNext(0);
        notifier.unlinkExercise(0);
        notifier.moveExercise(0, 1);
        notifier.markSaveUncertain('x');
        notifier.clearSaveUncertainty();

        expect(notifier.state, isNull);
      });
    });

    group('an uncertain save', () {
      test('freezes the title until the server answers, and saving clears it', () {
        final notifier = LiveActivityNotifier()..start();

        notifier.markSaveUncertain('Push day');
        expect(notifier.state!.pendingTitle, 'Push day');

        notifier.clearSaveUncertainty();
        expect(notifier.state!.pendingTitle, isNull);

        notifier.markSaveUncertain('Push day');
        notifier.markSaved(activityId: 3, title: 'Push day');
        expect(notifier.state!.pendingTitle, isNull);
        expect(notifier.state!.isSaved, isTrue);
      });

      test('survives other edits to the session', () {
        final notifier = LiveActivityNotifier()..start();
        notifier.markSaveUncertain('Push day');

        notifier.addExercise(1);
        notifier.finish();

        expect(notifier.state!.pendingTitle, 'Push day');
      });
    });
  });
}
