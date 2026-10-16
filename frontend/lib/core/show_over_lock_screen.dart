import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/activities/live/live_session.dart';
import 'keep_screen_on.dart';

/// Persists the "show over the lock screen" choice; same approach as
/// [KeepScreenOnStorage].
class ShowOverLockScreenStorage {
  const ShowOverLockScreenStorage();

  static const _key = 'show_over_lock_screen';

  /// Off when nothing is stored.
  Future<bool> read() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> write(bool value) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, value);
    } catch (_) {
      // Best-effort: the choice still applies for this run.
    }
  }
}

final showOverLockScreenStorageProvider = Provider<ShowOverLockScreenStorage>(
  (ref) => const ShowOverLockScreenStorage(),
);

/// Whether the app may appear over the lock screen during a live workout, so
/// that pressing the power button and waking the phone lands back on it
/// without unlocking. Off by default: the whole (logged-in) app is then
/// usable by anyone who wakes the phone. `main()` overrides the stored value.
final showOverLockScreenProvider = StateProvider<bool>((ref) => false);

/// Applies [showOverLockScreenProvider] to the Android window, but only while
/// a live workout is in progress -- outside one, nothing should show over the
/// lock screen whatever the setting says.
final showOverLockScreenSyncProvider = Provider<void>((ref) {
  if (!keepScreenOnSupported) return;
  final on = ref.watch(showOverLockScreenProvider) && ref.watch(liveActivityProvider) != null;
  () async {
    try {
      await screenChannel.invokeMethod<void>('setShowWhenLocked', on);
    } on PlatformException catch (error) {
      debugPrint('Could not change show-over-lock-screen: $error');
    } on MissingPluginException {
      // No native side (e.g. a test host): nothing to apply.
    }
  }();
});
