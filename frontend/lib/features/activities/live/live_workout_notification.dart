import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notification_taps.dart';
import '../../../core/router.dart';
import 'elapsed_timer.dart';
import 'live_session.dart';

/// What the Android "workout in progress" notification shows, kept separate
/// from the plugin so the sync logic below can be tested against a fake.
@immutable
class LiveWorkoutNotificationContent {
  const LiveWorkoutNotificationContent({
    required this.clockOrigin,
    required this.pausedElapsed,
    required this.exerciseCount,
  });

  /// The stopwatch's zero point (see [LiveActivitySession.clockOrigin]) --
  /// handed to Android's own chronometer, which ticks without the app
  /// re-posting anything every second.
  final DateTime clockOrigin;

  /// Non-null while paused: the frozen reading, shown as static text since a
  /// chronometer can't be told to hold still.
  final Duration? pausedElapsed;
  final int exerciseCount;

  @override
  bool operator ==(Object other) =>
      other is LiveWorkoutNotificationContent &&
      other.clockOrigin == clockOrigin &&
      other.pausedElapsed == pausedElapsed &&
      other.exerciseCount == exerciseCount;

  @override
  int get hashCode => Object.hash(clockOrigin, pausedElapsed, exerciseCount);
}

abstract class LiveWorkoutNotificationService {
  Future<void> show(LiveWorkoutNotificationContent content);
  Future<void> cancel();
}

/// Platforms with no persistent-notification support (web, desktop, tests).
class NoopLiveWorkoutNotificationService implements LiveWorkoutNotificationService {
  @override
  Future<void> show(LiveWorkoutNotificationContent content) async {}

  @override
  Future<void> cancel() async {}
}

/// An ongoing (non-swipeable) Android notification, hosted by a foreground
/// service so the OS keeps the app process alive for the length of the workout
/// (and is far less eager to kill it in the background). Tapping the
/// notification brings the app forward and calls [onTap] to route to the live
/// workout screen.
class AndroidLiveWorkoutNotificationService implements LiveWorkoutNotificationService {
  AndroidLiveWorkoutNotificationService({required this.onTap}) {
    // This notification carries no payload; reminders (see `workout_reminders.dart`) do.
    addNotificationTapListener((payload) {
      if (payload == null) onTap();
    });
  }

  static const _id = 1;
  static const _channelId = 'live_workout';

  final VoidCallback onTap;
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
    // Android 13+ requires a runtime grant; without it show() is silently dropped.
    await _android?.requestNotificationsPermission();
  }();

  @override
  Future<void> show(LiveWorkoutNotificationContent content) async {
    try {
      await _init();
      final paused = content.pausedElapsed;
      final count = content.exerciseCount;
      final exercises = '$count ${count == 1 ? 'exercise' : 'exercises'}';
      // (Re)starting an already-running foreground service just refreshes its
      // notification, so this doubles as the update path.
      await _android?.startForegroundService(
        id: _id,
        title: paused == null ? 'Workout in progress' : 'Workout paused',
        body: paused == null
            ? '$exercises · tap to return'
            : '${formatElapsed(paused)} · $exercises · tap to return',
        foregroundServiceTypes: {AndroidServiceForegroundType.foregroundServiceTypeSpecialUse},
        notificationDetails: AndroidNotificationDetails(
          _channelId,
          'Live workout',
          channelDescription: 'Shown while a live workout is under way',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          playSound: false,
          enableVibration: false,
          category: AndroidNotificationCategory.workout,
          showWhen: paused == null,
          usesChronometer: paused == null,
          when: content.clockOrigin.millisecondsSinceEpoch,
        ),
      );
    } catch (error) {
      // A notification is a convenience: never let it break the workout itself.
      debugPrint('Live workout notification failed: $error');
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _init();
      await _android?.stopForegroundService();
      await _plugin.cancel(id: _id);
    } catch (error) {
      debugPrint('Live workout notification cancel failed: $error');
    }
  }
}

final liveWorkoutNotificationServiceProvider = Provider<LiveWorkoutNotificationService>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return NoopLiveWorkoutNotificationService();
  }
  return AndroidLiveWorkoutNotificationService(
    onTap: () => ref.read(routerProvider).go('/activities/live'),
  );
});

/// Keeps the notification in step with [liveActivityProvider]: shown while a
/// workout is under way, updated as the stopwatch/exercises change, removed on
/// finish or discard. Watched once from the app root so it lives as long as
/// the app does.
final liveWorkoutNotificationSyncProvider = Provider<void>((ref) {
  final service = ref.watch(liveWorkoutNotificationServiceProvider);
  LiveWorkoutNotificationContent? last;

  void sync(LiveActivitySession? session) {
    if (session == null || session.endedAt != null) {
      if (last != null) service.cancel();
      last = null;
      return;
    }
    final content = LiveWorkoutNotificationContent(
      clockOrigin: session.clockOrigin,
      pausedElapsed: session.isPaused ? session.clockElapsedAt(session.pausedAt!) : null,
      exerciseCount: session.exercises.length,
    );
    if (content == last) return;
    last = content;
    service.show(content);
  }

  ref.listen<LiveActivitySession?>(liveActivityProvider, (_, next) => sync(next));
  sync(ref.read(liveActivityProvider));
});
