import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_notifier.dart';
import '../../core/auth/auth_state.dart';
import '../../core/router.dart';

// These strings are the contract with `MainActivity.kt`. They are repeated
// there as literals, and `test/features/routines/shortcut_contract_test.dart`
// fails if the two sides ever drift apart.

/// The platform channel to `MainActivity`.
const routineShortcutsChannelName = 'dev.bergercookie.dinatos/shortcuts';

/// Dart -> Android: `{routineId: int, name: String}` -> bool. Asks the
/// launcher to pin a home-screen shortcut for the routine (false when the
/// launcher cannot pin).
const pinShortcutMethod = 'pinShortcut';

/// Dart -> Android: the routine id the app was launched with from a shortcut,
/// once, or null.
const initialRoutineIdMethod = 'initialRoutineId';

/// Android -> Dart: a shortcut was tapped while the app was already running.
/// The argument is the routine id.
const routineLaunchedMethod = 'routineLaunched';

/// The action and extra of the intent a pinned shortcut fires.
const startRoutineIntentAction = 'dev.bergercookie.dinatos.action.START_ROUTINE';
const routineIdIntentExtra = 'routine_id';

/// The platform call failed (not "the launcher cannot pin": that is `false`).
class ShortcutException implements Exception {
  const ShortcutException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Pinned home-screen shortcuts that start a workout from a saved routine.
/// Apart from the Android implementation so the rest can be tested against a
/// fake, like the notification services.
abstract class RoutineShortcutService {
  /// Whether this platform can have routine shortcuts at all (Android only).
  bool get isSupported;

  /// Asks the launcher to pin a shortcut for [routineId]. Android shows its own
  /// confirmation. Returns false when the launcher cannot pin shortcuts. The
  /// shortcut id is stable per routine, so asking again updates the pinned one
  /// (for example after a rename) instead of adding a copy.
  Future<bool> pin({required int routineId, required String name});

  /// The routine whose shortcut cold-started the app, or null. Reports a launch
  /// once only: a second call returns null.
  Future<int?> initialRoutineId();

  /// Routines whose shortcut was tapped while the app was already running.
  Stream<int> get routineLaunches;
}

/// Platforms without home-screen shortcuts (web, desktop, iOS, tests).
class NoopRoutineShortcutService implements RoutineShortcutService {
  @override
  bool get isSupported => false;

  @override
  Future<bool> pin({required int routineId, required String name}) async => false;

  @override
  Future<int?> initialRoutineId() async => null;

  @override
  Stream<int> get routineLaunches => const Stream.empty();
}

class AndroidRoutineShortcutService implements RoutineShortcutService {
  AndroidRoutineShortcutService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(routineShortcutsChannelName) {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final _launches = StreamController<int>.broadcast();

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method == routineLaunchedMethod && call.arguments is int) {
      _launches.add(call.arguments as int);
    }
    return null;
  }

  @override
  bool get isSupported => true;

  @override
  Future<bool> pin({required int routineId, required String name}) async {
    try {
      final pinned = await _channel.invokeMethod<bool>(pinShortcutMethod, {
        'routineId': routineId,
        'name': name,
      });
      return pinned ?? false;
    } on PlatformException catch (error) {
      throw ShortcutException(error.message ?? 'Could not add the shortcut.');
    } on MissingPluginException {
      // No native side listening: a build without the bridge, or a test host.
      throw const ShortcutException('Shortcuts are not available in this build.');
    }
  }

  @override
  Future<int?> initialRoutineId() async {
    try {
      return await _channel.invokeMethod<int>(initialRoutineIdMethod);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Stream<int> get routineLaunches => _launches.stream;
}

final routineShortcutServiceProvider = Provider<RoutineShortcutService>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return NoopRoutineShortcutService();
  }
  return AndroidRoutineShortcutService();
});

/// The login state a shortcut launch waits on -- its own provider so tests can
/// feed it directly, like `reminderAuthProvider`.
final shortcutAuthProvider = Provider<AuthState>((ref) => ref.watch(authNotifierProvider));

/// A shortcut launch that has not been acted on yet: set when a shortcut is
/// tapped, cleared once the workout screen is opened. While nobody is signed in
/// it just waits, so the login comes first and the workout starts right after.
final pendingRoutineLaunchProvider = StateProvider<int?>((ref) => null);

/// Opens `/routines/<id>/start` for a pending shortcut launch as soon as the
/// user is signed in. Watched once from the app root.
final routineShortcutLaunchProvider = Provider<void>((ref) {
  final service = ref.watch(routineShortcutServiceProvider);

  void openIfReady() {
    final id = ref.read(pendingRoutineLaunchProvider);
    if (id == null || ref.read(shortcutAuthProvider) is! AuthAuthenticated) return;
    ref.read(pendingRoutineLaunchProvider.notifier).state = null;
    ref.read(routerProvider).go('/routines/$id/start');
  }

  ref.listen<int?>(pendingRoutineLaunchProvider, (_, _) => openIfReady());
  ref.listen<AuthState>(shortcutAuthProvider, (_, _) => openIfReady());

  final subscription = service.routineLaunches.listen(
    (id) => ref.read(pendingRoutineLaunchProvider.notifier).state = id,
  );
  ref.onDispose(subscription.cancel);

  var disposed = false;
  ref.onDispose(() => disposed = true);
  unawaited(
    service.initialRoutineId().then((id) {
      if (id != null && !disposed) ref.read(pendingRoutineLaunchProvider.notifier).state = id;
    }),
  );
});
