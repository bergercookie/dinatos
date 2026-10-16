import 'dart:io';

import 'package:dinatos_frontend/core/auth/auth_notifier.dart';
import 'package:dinatos_frontend/core/auth/token_storage.dart';
import 'package:dinatos_frontend/core/keep_screen_on.dart';
import 'package:dinatos_frontend/core/show_over_lock_screen.dart';
import 'package:dinatos_frontend/features/activities/live/live_session.dart';
import 'package:dinatos_frontend/features/activities/live/live_session_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

class _NoToken implements TokenStorage {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String token) async {}

  @override
  Future<void> clear() async {}
}

class _TestAuth extends AuthNotifier {
  _TestAuth() : super(buildMockDio(), _NoToken());
}

/// Everything the Dart side asks of the Android window, as `method(arg)`.
typedef _Calls = List<String>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late _Calls calls;

  void mockChannel([Object? Function(MethodCall call)? handler]) {
    messenger.setMockMethodCallHandler(screenChannel, (call) async {
      calls.add('${call.method}(${call.arguments})');
      return handler?.call(call);
    });
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    mockChannel();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(screenChannel, null);
  });

  /// A container with the sync provider alive, like the app root watching it.
  ProviderContainer app({bool setting = false, PersistedLiveSession? restored}) {
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith((ref) => _TestAuth()),
        showOverLockScreenProvider.overrideWith((ref) => setting),
        if (restored != null) restoredLiveSessionProvider.overrideWithValue(restored),
      ],
    );
    addTearDown(container.dispose);
    container.listen(showOverLockScreenSyncProvider, (_, _) {});
    return container;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  String lastShowWhenLocked() => calls.lastWhere((c) => c.startsWith('setShowWhenLocked'));

  group('storage', () {
    test('is off when nothing is stored', () async {
      expect(await const ShowOverLockScreenStorage().read(), isFalse);
    });

    test('round-trips both values', () async {
      await const ShowOverLockScreenStorage().write(true);
      expect(await const ShowOverLockScreenStorage().read(), isTrue);
      await const ShowOverLockScreenStorage().write(false);
      expect(await const ShowOverLockScreenStorage().read(), isFalse);
    });

    test('a value of the wrong type falls back to off rather than throwing', () async {
      SharedPreferences.setMockInitialValues({'show_over_lock_screen': 'yes'});
      expect(await const ShowOverLockScreenStorage().read(), isFalse);
    });

    test('is independent of the keep-screen-on setting', () async {
      await const KeepScreenOnStorage().write(true);
      expect(await const ShowOverLockScreenStorage().read(), isFalse);
      await const ShowOverLockScreenStorage().write(true);
      await const KeepScreenOnStorage().write(false);
      expect(await const ShowOverLockScreenStorage().read(), isTrue);
    });
  });

  group('when the window is asked to show over the lock screen', () {
    test('never with the setting off, workout or not', () async {
      final c = app();
      await settle();
      expect(lastShowWhenLocked(), 'setShowWhenLocked(false)');
      c.read(liveActivityProvider.notifier).start();
      await settle();
      expect(lastShowWhenLocked(), 'setShowWhenLocked(false)');
      expect(calls.where((c) => c == 'setShowWhenLocked(true)'), isEmpty);
    });

    test('never with the setting on but no workout in progress', () async {
      app(setting: true);
      await settle();
      expect(lastShowWhenLocked(), 'setShowWhenLocked(false)');
    });

    test('with the setting on, from the moment a workout starts', () async {
      final c = app(setting: true);
      await settle();
      c.read(liveActivityProvider.notifier).start();
      await settle();
      expect(lastShowWhenLocked(), 'setShowWhenLocked(true)');
    });

    test('stops when the workout is discarded', () async {
      final c = app(setting: true);
      c.read(liveActivityProvider.notifier).start();
      await settle();
      expect(lastShowWhenLocked(), 'setShowWhenLocked(true)');
      c.read(liveActivityProvider.notifier).discard();
      await settle();
      expect(lastShowWhenLocked(), 'setShowWhenLocked(false)');
    });

    test('stops when the setting is turned off mid-workout', () async {
      final c = app(setting: true);
      c.read(liveActivityProvider.notifier).start();
      await settle();
      c.read(showOverLockScreenProvider.notifier).state = false;
      await settle();
      expect(lastShowWhenLocked(), 'setShowWhenLocked(false)');
    });

    test('starts when the setting is turned on mid-workout', () async {
      final c = app();
      c.read(liveActivityProvider.notifier).start();
      await settle();
      c.read(showOverLockScreenProvider.notifier).state = true;
      await settle();
      expect(lastShowWhenLocked(), 'setShowWhenLocked(true)');
    });

    test('is already on at startup when a workout was restored from disk', () async {
      app(
        setting: true,
        restored: PersistedLiveSession(session: LiveActivitySession(startedAt: DateTime(2026))),
      );
      await settle();
      expect(calls, ['setShowWhenLocked(true)']);
    });

    test('a restored workout with the setting off stays hidden', () async {
      app(
        restored: PersistedLiveSession(session: LiveActivitySession(startedAt: DateTime(2026))),
      );
      await settle();
      expect(calls, ['setShowWhenLocked(false)']);
    });

    test(
      'a finished-but-unsaved workout (the summary screen) still counts as in progress',
      () async {
        // Documents current behaviour: the session is held until saved or
        // discarded, and the summary is where it is saved.
        final c = app(setting: true);
        final notifier = c.read(liveActivityProvider.notifier)..start();
        notifier.finish();
        await settle();
        expect(lastShowWhenLocked(), 'setShowWhenLocked(true)');
      },
    );

    test('does not touch keep-screen-on', () async {
      final c = app(setting: true);
      c.read(liveActivityProvider.notifier).start();
      await settle();
      expect(calls.where((c) => c.startsWith('setKeepScreenOn')), isEmpty);
    });
  });

  group('robustness', () {
    test('does nothing off Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final c = app(setting: true);
      c.read(liveActivityProvider.notifier).start();
      await settle();
      expect(calls, isEmpty);
    });

    test('a native error is swallowed, not thrown', () async {
      mockChannel((_) => throw PlatformException(code: 'boom'));
      final c = app(setting: true);
      c.read(liveActivityProvider.notifier).start();
      await settle();
      expect(calls, isNotEmpty);
    });

    test('a missing native side (no handler) is swallowed too', () async {
      messenger.setMockMethodCallHandler(screenChannel, null);
      final c = app(setting: true);
      c.read(liveActivityProvider.notifier).start();
      await settle();
    });
  });

  group('the native side', () {
    final kotlin = File(
      'android/app/src/main/kotlin/dev/bergercookie/dinatos_frontend/MainActivity.kt',
    ).readAsStringSync();

    test('listens on the channel the Dart side calls', () {
      expect(screenChannel.name, 'dev.bergercookie.dinatos/screen');
      expect(kotlin, contains('"${screenChannel.name}"'));
    });

    test('handles every method the Dart side sends', () {
      expect(kotlin, contains('"setShowWhenLocked"'));
      expect(kotlin, contains('"setKeepScreenOn"'));
    });

    test('uses the non-deprecated API where available, with a flag fallback below it', () {
      expect(kotlin, contains('setShowWhenLocked(on)'));
      expect(kotlin, contains('O_MR1'));
      expect(kotlin, contains('FLAG_SHOW_WHEN_LOCKED'));
    });

    test('never asks to turn the screen on or dismiss the keyguard', () {
      // Showing over the lock screen must not unlock the phone.
      expect(kotlin, isNot(contains('requestDismissKeyguard')));
      expect(kotlin, isNot(contains('FLAG_DISMISS_KEYGUARD')));
      expect(kotlin, isNot(contains('setTurnScreenOn')));
    });
  });
}
