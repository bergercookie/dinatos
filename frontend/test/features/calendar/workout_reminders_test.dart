import 'package:dinatos_frontend/core/auth/auth_state.dart';
import 'package:dinatos_frontend/features/calendar/planned_workouts_providers.dart';
import 'package:dinatos_frontend/features/calendar/workout_reminders.dart';
import 'package:dinatos_frontend/models/planned_workout.dart';
import 'package:dinatos_frontend/models/user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingService implements WorkoutReminderService {
  final calls = <List<WorkoutReminder>>[];

  @override
  Future<void> replaceAll(List<WorkoutReminder> reminders) async => calls.add(reminders);
}

PlannedWorkout _plan(int id, DateTime at, {int? reminder = 30, int? done, String title = 'Push'}) =>
    PlannedWorkout(
      id: id,
      title: title,
      scheduledAt: at,
      reminderMinutes: reminder,
      completedActivityId: done,
    );

void main() {
  final now = DateTime(2030, 5, 10, 12);

  group('upcomingReminders', () {
    test('keeps only unfinished plans with a reminder still in the future, soonest first', () {
      final reminders = upcomingReminders([
        _plan(1, DateTime(2030, 5, 12, 9)),
        _plan(2, DateTime(2030, 5, 10, 18)),
        _plan(3, DateTime(2030, 5, 11, 9), reminder: null),
        _plan(4, DateTime(2030, 5, 11, 9), done: 8),
        _plan(5, DateTime(2030, 5, 10, 12, 20)), // reminder was due at 11:50: gone
      ], now);

      expect(reminders.map((r) => r.plannedId), [2, 1]);
      expect(reminders.first.at, DateTime(2030, 5, 10, 17, 30));
      expect(reminders.first.startsAt, DateTime(2030, 5, 10, 18));
    });

    test('is capped at the limit', () {
      final plans = [for (var i = 1; i <= 5; i++) _plan(i, DateTime(2030, 6, i, 9))];
      expect(upcomingReminders(plans, now, limit: 2).map((r) => r.plannedId), [1, 2]);
    });
  });

  test('plannedIdFromPayload only understands planned-workout payloads', () {
    expect(plannedIdFromPayload('planned:42'), 42);
    expect(plannedIdFromPayload('planned:x'), isNull);
    expect(plannedIdFromPayload('other'), isNull);
    expect(plannedIdFromPayload(null), isNull);
  });

  group('workoutReminderSyncProvider', () {
    ProviderContainer container(
      AuthState auth,
      _RecordingService service,
      Future<List<PlannedWorkout>> Function() plans,
    ) {
      final c = ProviderContainer(
        overrides: [
          reminderAuthProvider.overrideWithValue(auth),
          workoutReminderServiceProvider.overrideWithValue(service),
          plannedWorkoutListProvider.overrideWith((ref) => plans()),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    final user = const User(id: 1, email: 'a@b.c', isAdmin: false);

    test('schedules the reminders of an authenticated user', () async {
      final service = _RecordingService();
      final later = DateTime.now().add(const Duration(days: 2));
      final c = container(
        AuthAuthenticated(token: 't', user: user),
        service,
        () async => [_plan(1, later)],
      );

      c.listen(workoutReminderSyncProvider, (_, _) {});
      await c.read(plannedWorkoutListProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(service.calls.last.map((r) => r.plannedId), [1]);
    });

    test('clears reminders on logout but leaves them alone while the login is unknown', () async {
      final unknown = _RecordingService();
      container(const AuthUnknown(), unknown, () async => []).read(workoutReminderSyncProvider);
      expect(unknown.calls, isEmpty);

      final loggedOut = _RecordingService();
      container(
        const AuthUnauthenticated(),
        loggedOut,
        () async => [],
      ).read(workoutReminderSyncProvider);
      expect(loggedOut.calls, [isEmpty]);
    });

    test('keeps what is scheduled when the plans cannot be fetched', () async {
      final service = _RecordingService();
      final c = container(
        AuthAuthenticated(token: 't', user: user),
        service,
        () async => throw Exception('offline'),
      );

      c.listen(workoutReminderSyncProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      expect(service.calls, isEmpty);
    });
  });
}
