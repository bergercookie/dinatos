import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// `flutter_local_notifications` has one tap callback for the whole app --
/// whichever `initialize()` ran last wins -- but this app posts two kinds of
/// notification (the live workout's, and planned-workout reminders), each
/// owned by its own service. Every service passes [dispatchNotificationTap]
/// as the callback and registers a listener that acts on the payloads it owns.
typedef NotificationTapListener = void Function(String? payload);

final _listeners = <NotificationTapListener>[];

void addNotificationTapListener(NotificationTapListener listener) => _listeners.add(listener);

void dispatchNotificationTap(NotificationResponse response) {
  for (final listener in List.of(_listeners)) {
    listener(response.payload);
  }
}
