import 'package:dinatos_frontend/core/auth/auth_notifier.dart';
import 'package:dinatos_frontend/core/auth/token_storage.dart';
import 'package:dinatos_frontend/core/keep_screen_on.dart';
import 'package:dinatos_frontend/core/show_over_lock_screen.dart';
import 'package:dinatos_frontend/features/profile/profile_providers.dart';
import 'package:dinatos_frontend/features/profile/profile_screen.dart';
import 'package:dinatos_frontend/models/profile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A widget test on [platform]; the override must be cleared inside the test
  /// body, since the framework checks for it before any tearDown runs.
  void platformTest(
    String description,
    TargetPlatform platform,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(description, (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<ProviderContainer> open(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith((ref) => _TestAuth()),
        profileProvider.overrideWith(
          (ref) async => const Profile(heightCm: 180, unitSystem: UnitSystem.metric),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  final lockSwitch = find.widgetWithText(SwitchListTile, 'Show workout on lock screen');

  platformTest(
    'on Android: shown, off by default, with the exposure warning',
    TargetPlatform.android,
    (tester) async {
      await open(tester);
      await tester.scrollUntilVisible(lockSwitch, 200, scrollable: find.byType(Scrollable).first);

      expect(tester.widget<SwitchListTile>(lockSwitch).value, isFalse);
      expect(find.textContaining('Anyone who picks up the phone'), findsOneWidget);
    },
  );

  platformTest(
    'on Android: toggling updates the provider and persists, independently',
    TargetPlatform.android,
    (tester) async {
      final container = await open(tester);
      await tester.scrollUntilVisible(lockSwitch, 200, scrollable: find.byType(Scrollable).first);

      await tester.tap(lockSwitch);
      await tester.pumpAndSettle();
      expect(container.read(showOverLockScreenProvider), isTrue);
      expect(container.read(keepScreenOnProvider), isFalse);
      expect(await const ShowOverLockScreenStorage().read(), isTrue);
      expect(await const KeepScreenOnStorage().read(), isFalse);

      await tester.tap(lockSwitch);
      await tester.pumpAndSettle();
      expect(container.read(showOverLockScreenProvider), isFalse);
      expect(await const ShowOverLockScreenStorage().read(), isFalse);
    },
  );

  platformTest('on Android: reflects a value restored at startup', TargetPlatform.android, (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith((ref) => _TestAuth()),
        showOverLockScreenProvider.overrideWith((ref) => true),
        profileProvider.overrideWith(
          (ref) async => const Profile(heightCm: 180, unitSystem: UnitSystem.metric),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(lockSwitch, 200, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<SwitchListTile>(lockSwitch).value, isTrue);
  });

  platformTest('off Android: neither screen switch is offered', TargetPlatform.linux, (
    tester,
  ) async {
    await open(tester);
    expect(lockSwitch, findsNothing);
    expect(find.widgetWithText(SwitchListTile, 'Keep screen on'), findsNothing);
  });
}
