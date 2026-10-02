import 'package:dinatos_frontend/features/activities/widgets/training_streak.dart';
import 'package:dinatos_frontend/models/activity.dart';
import 'package:flutter_test/flutter_test.dart';

Activity _activityOn(DateTime date) => Activity(title: 't', startedAt: date, exercises: const []);

void main() {
  group('trainingDatesFrom', () {
    test('collects distinct local calendar dates, ignoring time of day', () {
      final activities = [
        _activityOn(DateTime(2026, 3, 1, 8)),
        _activityOn(DateTime(2026, 3, 1, 19)),
        _activityOn(DateTime(2026, 3, 2, 7)),
      ];

      expect(trainingDatesFrom(activities), {DateTime(2026, 3, 1), DateTime(2026, 3, 2)});
    });
  });

  group('currentDayStreak', () {
    test('counts consecutive days ending today', () {
      final now = DateTime(2026, 3, 10);
      final dates = {DateTime(2026, 3, 8), DateTime(2026, 3, 9), DateTime(2026, 3, 10)};

      expect(currentDayStreak(dates, now: now), 3);
    });

    test("doesn't break the streak just because today hasn't been trained yet", () {
      final now = DateTime(2026, 3, 10);
      final dates = {DateTime(2026, 3, 8), DateTime(2026, 3, 9)};

      expect(currentDayStreak(dates, now: now), 2);
    });

    test('is zero once a day was actually skipped', () {
      final now = DateTime(2026, 3, 10);
      final dates = {DateTime(2026, 3, 7), DateTime(2026, 3, 8)};

      expect(currentDayStreak(dates, now: now), 0);
    });

    test('is zero for no training history at all', () {
      expect(currentDayStreak(const {}, now: DateTime(2026, 3, 10)), 0);
    });
  });

  group('currentWeekStreak', () {
    test('counts consecutive Monday-start weeks with at least one session', () {
      // 2026-03-02 is a Monday.
      final now = DateTime(2026, 3, 16);
      final dates = {
        DateTime(2026, 3, 2), // week of 3/2
        DateTime(2026, 3, 11), // week of 3/9
        DateTime(2026, 3, 16), // week of 3/16 (this week)
      };

      expect(currentWeekStreak(dates, now: now), 3);
    });

    test("doesn't break the streak just because this week hasn't been trained yet", () {
      final now = DateTime(2026, 3, 16);
      final dates = {DateTime(2026, 3, 2), DateTime(2026, 3, 9)};

      expect(currentWeekStreak(dates, now: now), 2);
    });

    test('is zero once a whole week was skipped', () {
      final now = DateTime(2026, 3, 23);
      final dates = {DateTime(2026, 3, 2)};

      expect(currentWeekStreak(dates, now: now), 0);
    });
  });
}
