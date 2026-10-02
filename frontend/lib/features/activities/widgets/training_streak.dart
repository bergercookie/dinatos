import '../../../models/activity.dart';

/// Normalizes [dt] to just its local calendar date (midnight) -- so set
/// membership and comparisons below ignore time-of-day entirely.
DateTime dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Every distinct local calendar date on which at least one activity was
/// logged -- what the training calendar marks and the streaks below count
/// over. `startedAt` is UTC-aware (see `Activity.fromJson`), so this always
/// converts to local before taking the date, the same way the activity list
/// screen's own date formatting does.
Set<DateTime> trainingDatesFrom(List<Activity> activities) =>
    activities.map((activity) => dateOnly(activity.startedAt.toLocal())).toSet();

/// The current "day streak": consecutive calendar days with at least one
/// workout, counting backward from today. Today not having a workout *yet*
/// doesn't break a streak that's still alive from yesterday -- only a day
/// that was actually skipped does, so logging first thing tomorrow instead
/// of tonight doesn't cost the streak.
int currentDayStreak(Set<DateTime> trainingDates, {DateTime? now}) {
  final today = dateOnly(now ?? DateTime.now());
  var cursor = trainingDates.contains(today) ? today : today.subtract(const Duration(days: 1));
  var streak = 0;
  while (trainingDates.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

/// The Monday that starts [date]'s (Monday-start, ISO-style) week.
DateTime weekStart(DateTime date) => date.subtract(Duration(days: date.weekday - 1));

/// The current "week streak": consecutive Monday-start weeks with at least
/// one workout, counting backward from this week -- forgiving the same way
/// [currentDayStreak] is: this week not having a workout yet doesn't break a
/// streak still alive from last week.
int currentWeekStreak(Set<DateTime> trainingDates, {DateTime? now}) {
  final trainedWeeks = trainingDates.map(weekStart).toSet();
  final thisWeek = weekStart(dateOnly(now ?? DateTime.now()));
  var cursor = trainedWeeks.contains(thisWeek)
      ? thisWeek
      : thisWeek.subtract(const Duration(days: 7));
  var streak = 0;
  while (trainedWeeks.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 7));
  }
  return streak;
}
