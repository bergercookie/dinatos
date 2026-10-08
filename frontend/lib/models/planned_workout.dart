/// A workout scheduled for a future time: one entry of the training calendar.
/// Not an [Activity] -- it only becomes one when a workout started from it is
/// saved, at which point [completedActivityId] is set.
class PlannedWorkout {
  const PlannedWorkout({
    this.id,
    required this.title,
    this.notes,
    required this.scheduledAt,
    this.routineId,
    this.durationMinutes = 60,
    this.reminderMinutes = 30,
    this.completedActivityId,
  });

  factory PlannedWorkout.fromJson(Map<String, dynamic> json) => PlannedWorkout(
    id: json['id'] as int,
    title: json['title'] as String,
    notes: json['notes'] as String?,
    scheduledAt: DateTime.parse(json['scheduled_at'] as String).toLocal(),
    routineId: json['routine_id'] as int?,
    durationMinutes: json['duration_minutes'] as int,
    reminderMinutes: json['reminder_minutes'] as int?,
    completedActivityId: json['completed_activity_id'] as int?,
  );

  final int? id;
  final String title;
  final String? notes;
  final DateTime scheduledAt;
  final int? routineId;
  final int durationMinutes;

  /// Minutes before [scheduledAt] to remind; null for no reminder.
  final int? reminderMinutes;
  final int? completedActivityId;

  bool get isCompleted => completedActivityId != null;

  /// When the phone should remind, or null if it should not.
  DateTime? get reminderAt {
    final minutes = reminderMinutes;
    return minutes == null ? null : scheduledAt.subtract(Duration(minutes: minutes));
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'notes': notes,
    'scheduled_at': scheduledAt.toUtc().toIso8601String(),
    'routine_id': routineId,
    'duration_minutes': durationMinutes,
    'reminder_minutes': reminderMinutes,
  };
}

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

/// The planned workouts still to do on [now]'s calendar day: not yet
/// completed, and scheduled today -- including one whose time already passed
/// this morning, since it is still the day to do it. Earliest first.
List<PlannedWorkout> todaysPlannedWorkouts(List<PlannedWorkout> all, DateTime now) {
  final today = _day(now);
  return all.where((p) => !p.isCompleted && _day(p.scheduledAt.toLocal()) == today).toList()
    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
}

/// The days (local midnight) that have a workout still to do, for the
/// calendar's markers.
Set<DateTime> plannedDates(List<PlannedWorkout> all) => {
  for (final p in all)
    if (!p.isCompleted) _day(p.scheduledAt.toLocal()),
};

/// Workouts still to do from [now] on, soonest first -- what the Home
/// screen's "Upcoming" card lists. One earlier today still counts (see
/// [todaysPlannedWorkouts]).
List<PlannedWorkout> upcomingPlannedWorkouts(List<PlannedWorkout> all, DateTime now) {
  final today = _day(now);
  return all.where((p) => !p.isCompleted && !_day(p.scheduledAt.toLocal()).isBefore(today)).toList()
    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
}
