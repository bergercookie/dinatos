import 'package:dinatos_frontend/core/api_exception.dart';
import 'package:dinatos_frontend/core/auth/auth_notifier.dart';
import 'package:dinatos_frontend/core/auth/token_storage.dart';
import 'package:dinatos_frontend/core/dio_provider.dart';
import 'package:dinatos_frontend/features/admin/admin_providers.dart';
import 'package:dinatos_frontend/features/admin/admin_repository.dart';
import 'package:dinatos_frontend/features/admin/admin_screen.dart';
import 'package:dinatos_frontend/models/admin_settings.dart';
import 'package:dinatos_frontend/models/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fakes.dart';

class MockAdminRepository extends Mock implements AdminRepository {}

void main() {
  late MockAdminRepository admin;
  late AdminSettings current;

  setUp(() {
    admin = MockAdminRepository();
    current = const AdminSettings(allowRegistration: true, allowRegistrationLocked: false);
    when(() => admin.getSettings()).thenAnswer((_) async => current);
  });

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        adminRepositoryProvider.overrideWithValue(admin),
        adminUsersProvider.overrideWith(
          (ref) async => const [User(id: 1, email: 'a@example.com', isAdmin: true)],
        ),
        dioProvider.overrideWithValue(buildMockDio()),
        tokenStorageProvider.overrideWithValue(TokenStorage(storage: FakeSecureStore())),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AdminScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder switchTile() => find.widgetWithText(SwitchListTile, 'Allow registration');

  testWidgets('shows registration as on and lets the admin turn it off', (tester) async {
    when(() => admin.setAllowRegistration(allowed: false)).thenAnswer((_) async {
      current = const AdminSettings(allowRegistration: false, allowRegistrationLocked: false);
      return current;
    });
    await pump(tester);

    expect(tester.widget<SwitchListTile>(switchTile()).value, isTrue);
    expect(find.textContaining('Locked by the server settings'), findsNothing);

    await tester.tap(switchTile());
    await tester.pumpAndSettle();

    verify(() => admin.setAllowRegistration(allowed: false)).called(1);
    expect(tester.widget<SwitchListTile>(switchTile()).value, isFalse);
    expect(find.textContaining('Only an admin can add accounts'), findsOneWidget);
  });

  testWidgets('lets the admin turn registration back on', (tester) async {
    current = const AdminSettings(allowRegistration: false, allowRegistrationLocked: false);
    when(() => admin.setAllowRegistration(allowed: true)).thenAnswer((_) async {
      current = const AdminSettings(allowRegistration: true, allowRegistrationLocked: false);
      return current;
    });
    await pump(tester);

    await tester.tap(switchTile());
    await tester.pumpAndSettle();

    verify(() => admin.setAllowRegistration(allowed: true)).called(1);
    expect(tester.widget<SwitchListTile>(switchTile()).value, isTrue);
  });

  testWidgets('is disabled and explains why while the environment variable is set', (tester) async {
    current = const AdminSettings(allowRegistration: false, allowRegistrationLocked: true);
    await pump(tester);

    final tile = tester.widget<SwitchListTile>(switchTile());
    expect(tile.onChanged, isNull, reason: 'the switch must be disabled');
    expect(tile.value, isFalse);
    expect(find.text('Locked by the server settings'), findsOneWidget);
    expect(find.textContaining('DINATOS_ALLOW_REGISTRATION is set to false'), findsOneWidget);
    expect(find.textContaining('clear the variable and restart the server'), findsOneWidget);

    await tester.tap(switchTile());
    await tester.pumpAndSettle();
    verifyNever(() => admin.setAllowRegistration(allowed: any(named: 'allowed')));
  });

  testWidgets('a locked "on" value is shown as on', (tester) async {
    current = const AdminSettings(allowRegistration: true, allowRegistrationLocked: true);
    await pump(tester);

    expect(tester.widget<SwitchListTile>(switchTile()).value, isTrue);
    expect(find.textContaining('DINATOS_ALLOW_REGISTRATION is set to true'), findsOneWidget);
  });

  testWidgets('a refused change shows the server message and re-reads the lock', (tester) async {
    when(() => admin.setAllowRegistration(allowed: false)).thenAnswer((_) async {
      // The operator set the variable after the screen loaded.
      current = const AdminSettings(allowRegistration: true, allowRegistrationLocked: true);
      throw const ApiException('DINATOS_ALLOW_REGISTRATION is set', statusCode: 409);
    });
    await pump(tester);

    await tester.tap(switchTile());
    await tester.pumpAndSettle();

    expect(find.textContaining('DINATOS_ALLOW_REGISTRATION is set'), findsWidgets);
    expect(tester.widget<SwitchListTile>(switchTile()).onChanged, isNull);
  });

  testWidgets('a failed load shows an error with a retry', (tester) async {
    var calls = 0;
    when(() => admin.getSettings()).thenAnswer((_) async {
      calls++;
      if (calls == 1) throw const ApiException('boom', statusCode: 500);
      return current;
    });
    await pump(tester);

    expect(find.text('Could not load the registration setting'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(switchTile(), findsOneWidget);
  });
}
