import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/auth/auth_notifier.dart';
import '../../core/auth/auth_state.dart';
import '../../core/notification_taps.dart';
import '../../core/router.dart';
import '../../models/planned_workout.dart';
import 'planned_workouts_providers.dart';

const _payloadPrefix = 'planned:';

/// One reminder to show: when, and which planned workout it is for.
@immutable
class WorkoutReminder {
  const WorkoutReminder({
    required this.plannedId,
    required this.title,
    required this.startsAt,
    required this.at,
  });

  final int plannedId;
  final String title;
  final DateTime startsAt;

  /// When to notify -- [startsAt] minus the plan's reminder lead time.
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is WorkoutReminder &&
      other.plannedId == plannedId &&
      other.title == title &&
      other.startsAt == startsAt &&
      other.at == at;

  @override
  int get hashCode => Object.hash(plannedId, title, startsAt, at);
}

/// The reminders that still make sense at [now]: workouts not yet done, with a
/// reminder set, whose reminder time has not passed, soonest first. Capped, as
/// the OS limits how many alarms an app may hold (and a person far from
/// planning 50 sessions ahead is better served by the next ones being right).
List<WorkoutReminder> upcomingReminders(
  List<PlannedWorkout> plans,
  DateTime now, {
  int limit = 50,
}) {
  final reminders = <WorkoutReminder>[
    for (final plan in plans)
      if (plan.id != null && !plan.isCompleted && plan.reminderAt != null)
        if (plan.reminderAt!.isAfter(now))
          WorkoutReminder(
            plannedId: plan.id!,
            title: plan.title,
            startsAt: plan.scheduledAt,
            at: plan.reminderAt!,
          ),
  ]..sort((a, b) => a.at.compareTo(b.at));
  return reminders.take(limit).toList();
}

/// What actually schedules the notifications, apart from the sync logic below
/// so that can be tested against a fake.
abstract class WorkoutReminderService {
  /// Makes the scheduled reminders exactly [reminders]: anything scheduled
  /// before and not listed is cancelled.
  Future<void> replaceAll(List<WorkoutReminder> reminders);
}

/// Platforms with no scheduled-notification support (web, desktop, tests).
class NoopWorkoutReminderService implements WorkoutReminderService {
  @override
  Future<void> replaceAll(List<WorkoutReminder> reminders) async {}
}

/// Android: one scheduled local notification per reminder, which survives the
/// app being closed (and, via the plugin's boot receiver, a reboot). Tapping it
/// calls [onTap] with the planned workout's id, to start that workout.
class AndroidWorkoutReminderService implements WorkoutReminderService {
  AndroidWorkoutReminderService({required this.onTap}) {
    addNotificationTapListener((payload) {
      final id = plannedIdFromPayload(payload);
      if (id != null) onTap(id);
    });
  }

  static const _channelId = 'planned_workouts';

  /// Offsets reminders' ids away from the live workout notification's (1).
  static const _idBase = 1000;

  final void Function(int plannedId) onTap;
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> _init() => _ready ??= () async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: dispatchNotificationTap,
    );
    // Android 13+ requires a runtime grant; without it scheduled notifications are dropped.
    await _android?.requestNotificationsPermission();
    // The app was opened by tapping a reminder while it was not running.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final id = plannedIdFromPayload(launch?.notificationResponse?.payload);
    if (launch?.didNotificationLaunchApp == true && id != null) onTap(id);
  }();

  @override
  Future<void> replaceAll(List<WorkoutReminder> reminders) async {
    try {
      await _init();
      for (final pending in await _plugin.pendingNotificationRequests()) {
        if (pending.payload?.startsWith(_payloadPrefix) ?? false) {
          await _plugin.cancel(id: pending.id);
        }
      }
      final time = DateFormat.Hm();
      for (final reminder in reminders) {
        await _plugin.zonedSchedule(
          id: _idBase + reminder.plannedId,
          title: reminder.title,
          body: 'Starts at ${time.format(reminder.startsAt)} · tap to start the workout',
          // An absolute instant: UTC is fine, the OS shows it in local time.
          scheduledDate: tz.TZDateTime.from(reminder.at, tz.UTC),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              'Planned workouts',
              channelDescription: 'Reminders for workouts you scheduled on the calendar',
              importance: Importance.high,
              priority: Priority.high,
              category: AndroidNotificationCategory.reminder,
            ),
          ),
          // Inexact (may fire a few minutes late in doze) so no exact-alarm
          // permission -- which Play restricts -- is needed for a reminder.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: '$_payloadPrefix${reminder.plannedId}',
        );
      }
    } catch (error) {
      // A reminder is a convenience: never let it break the app.
      debugPrint('Scheduling workout reminders failed: $error');
    }
  }
}

/// The planned workout's id out of a reminder's payload, or null for any other.
int? plannedIdFromPayload(String? payload) {
  if (payload == null || !payload.startsWith(_payloadPrefix)) return null;
  return int.tryParse(payload.substring(_payloadPrefix.length));
}

final workoutReminderServiceProvider = Provider<WorkoutReminderService>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return NoopWorkoutReminderService();
  }
  return AndroidWorkoutReminderService(
    onTap: (id) => ref.read(routerProvider).go('/activities/plan/$id/start'),
  );
});

/// The login state the reminders follow -- its own provider so tests can feed
/// it directly instead of standing up a whole [AuthNotifier].
final reminderAuthProvider = Provider<AuthState>((ref) => ref.watch(authNotifierProvider));

/// Keeps the scheduled reminders in step with the planned workouts: re-synced
/// whenever the list changes (a workout scheduled, moved, deleted or done),
/// and cleared on logout. Watched once from the app root.
final workoutReminderSyncProvider = Provider<void>((ref) {
  final service = ref.watch(workoutReminderServiceProvider);
  final auth = ref.watch(reminderAuthProvider);
  if (auth is! AuthAuthenticated) {
    // Another account (or nobody) must not get this one's reminders. While the
    // login is still being checked at startup, leave what is scheduled alone:
    // being offline then must not cancel tomorrow's reminder.
    if (auth is AuthUnauthenticated) service.replaceAll(const []);
    return;
  }
  final plans = ref.watch(plannedWorkoutListProvider);
  plans.whenData((data) => service.replaceAll(upcomingReminders(data, DateTime.now())));
});
