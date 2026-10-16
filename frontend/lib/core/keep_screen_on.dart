import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the "keep the screen on" choice; same approach (and reasoning) as
/// `ThemeModeStorage`.
class KeepScreenOnStorage {
  const KeepScreenOnStorage();

  static const _key = 'keep_screen_on';

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

final keepScreenOnStorageProvider = Provider<KeepScreenOnStorage>(
  (ref) => const KeepScreenOnStorage(),
);

/// Whether the screen should stay on while the app is in the foreground.
/// `main()` overrides the starting value from storage.
final keepScreenOnProvider = StateProvider<bool>((ref) => false);

/// Only Android has the window flag this drives.
bool get keepScreenOnSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Native window flags (keep-on, show-when-locked); see `MainActivity.kt`.
const screenChannel = MethodChannel('dev.bergercookie.dinatos/screen');

/// Applies [keepScreenOnProvider] to the Android window. Watched once from the
/// app root, like the notification sync providers.
final keepScreenOnSyncProvider = Provider<void>((ref) {
  if (!keepScreenOnSupported) return;
  Future<void> apply(bool on) async {
    try {
      await screenChannel.invokeMethod<void>('setKeepScreenOn', on);
    } on PlatformException catch (error) {
      debugPrint('Could not change keep-screen-on: $error');
    } on MissingPluginException {
      // No native side (e.g. a test host): nothing to apply.
    }
  }

  apply(ref.read(keepScreenOnProvider));
  ref.listen(keepScreenOnProvider, (_, on) => apply(on));
});
