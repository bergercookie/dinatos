import 'package:dinatos_frontend/models/planned_workout.dart';
import 'package:flutter_test/flutter_test.dart';

PlannedWorkout _plan(int id, DateTime at, {int? done, int? reminder = 30}) => PlannedWorkout(
  id: id,
  title: 'Plan $id',
  scheduledAt: at,
  completedActivityId: done,
  reminderMinutes: reminder,
);

void main() {
  final now = DateTime(2030, 5, 10, 12);

  test('fromJson reads UTC into local time and toJson writes UTC back', () {
    final plan = PlannedWorkout.fromJson({
      'id': 3,
      'title': 'Legs',
      'notes': 'heavy',
      'scheduled_at': '2030-05-10T18:00:00Z',
      'routine_id': 7,
      'duration_minutes': 75,
      'reminder_minutes': null,
      'completed_activity_id': null,
    });

    expect(plan.scheduledAt.isUtc, isFalse);
    expect(plan.scheduledAt.isAtSameMomentAs(DateTime.utc(2030, 5, 10, 18)), isTrue);
    expect(plan.reminderMinutes, isNull);
    expect(plan.reminderAt, isNull);
    expect(plan.toJson()['scheduled_at'], '2030-05-10T18:00:00.000Z');
    expect(plan.toJson()['routine_id'], 7);
    expect(plan.toJson().containsKey('id'), isFalse);
  });

  test('reminderAt is the start minus the lead time', () {
    final plan = _plan(1, DateTime(2030, 5, 10, 18), reminder: 45);
    expect(plan.reminderAt, DateTime(2030, 5, 10, 17, 15));
  });

  test('todaysPlannedWorkouts: today only, not done, earliest first, earlier today included', () {
    final plans = [
      _plan(1, DateTime(2030, 5, 10, 19)),
      _plan(2, DateTime(2030, 5, 10, 7)),
      _plan(3, DateTime(2030, 5, 10, 9), done: 5),
      _plan(4, DateTime(2030, 5, 11, 9)),
      _plan(5, DateTime(2030, 5, 9, 23, 59)),
    ];

    expect(todaysPlannedWorkouts(plans, now).map((p) => p.id), [2, 1]);
  });

  test('upcomingPlannedWorkouts skips done and past days, soonest first', () {
    final plans = [
      _plan(1, DateTime(2030, 5, 12, 9)),
      _plan(2, DateTime(2030, 5, 10, 7)),
      _plan(3, DateTime(2030, 5, 11, 9), done: 1),
      _plan(4, DateTime(2030, 5, 9, 9)),
    ];

    expect(upcomingPlannedWorkouts(plans, now).map((p) => p.id), [2, 1]);
  });

  test('plannedDates are the days still to do', () {
    final dates = plannedDates([
      _plan(1, DateTime(2030, 5, 12, 9)),
      _plan(2, DateTime(2030, 5, 12, 18)),
      _plan(3, DateTime(2030, 5, 13, 9), done: 1),
    ]);

    expect(dates, {DateTime(2030, 5, 12)});
  });
}
