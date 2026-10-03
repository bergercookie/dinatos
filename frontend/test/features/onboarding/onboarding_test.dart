import 'package:dinatos_frontend/core/auth/auth_notifier.dart';
import 'package:dinatos_frontend/core/auth/auth_state.dart';
import 'package:dinatos_frontend/core/auth/token_storage.dart';
import 'package:dinatos_frontend/features/onboarding/onboarding_controller.dart';
import 'package:dinatos_frontend/features/onboarding/onboarding_overlay.dart';
import 'package:dinatos_frontend/features/onboarding/onboarding_steps.dart';
import 'package:dinatos_frontend/models/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fakes.dart';

class _MemoryStorage implements OnboardingStorage {
  final seen = <int>{};

  @override
  Future<bool> hasSeen(int userId) async => seen.contains(userId);

  @override
  Future<void> markSeen(int userId) async => seen.add(userId);
}

class _NoToken extends TokenStorage {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String token) async {}

  @override
  Future<void> clear() async {}
}

class _TestAuth extends AuthNotifier {
  _TestAuth() : super(buildMockDio(), _NoToken());

  void signInAs(AuthState next) => state = next;
}

const _user = User(id: 7, email: 'a@example.com', isAdmin: false);
final _signedIn = AuthAuthenticated(token: 't', user: _user);

final _steps = [
  const TourStep(id: 'welcome', title: 'Welcome', body: 'Hi', primaryLabel: 'Start tour'),
  TourStep(
    id: 'go',
    title: 'Press go',
    body: 'Press the button',
    target: 'go',
    modal: true,
    advanceOnLocation: (path) => path == '/next',
    advanceOnEvent: 'saved',
  ),
  const TourStep(id: 'end', title: 'All set', body: 'Bye', primaryLabel: 'Finish'),
];

void main() {
  group('OnboardingController', () {
    late _MemoryStorage storage;
    late OnboardingController controller;

    setUp(() {
      storage = _MemoryStorage();
      controller = OnboardingController(storage, _steps);
    });

    test('starts for an account that has not seen the tour', () async {
      await controller.userSignedIn(7);

      expect(controller.currentStep?.id, 'welcome');
    });

    test('does not start for an account that has', () async {
      storage.seen.add(7);

      await controller.userSignedIn(7);

      expect(controller.state.active, isFalse);
    });

    test('finishing, and skipping, are remembered per account', () async {
      await controller.userSignedIn(7);
      controller.next();
      controller.next();
      expect(controller.currentStep?.id, 'end');
      controller.next();

      expect(controller.state.active, isFalse);
      expect(storage.seen, {7});

      await controller.userSignedIn(8); // a different account, same device
      expect(controller.currentStep?.id, 'welcome');
      controller.finish(); // "Skip tour"
      expect(storage.seen, {7, 8});
    });

    test('a step advances on its own navigation or event, and on nothing else', () async {
      await controller.userSignedIn(7);
      controller.next();

      controller.locationChanged('/elsewhere');
      controller.event('something-else');
      expect(controller.currentStep?.id, 'go');

      controller.event('saved');
      expect(controller.currentStep?.id, 'end');
    });

    test('a step advances when the app navigates where it was waiting for', () async {
      await controller.userSignedIn(7);
      controller.next();

      controller.locationChanged('/next');

      expect(controller.currentStep?.id, 'end');
    });

    test('signing out ends the tour without recording it as seen', () async {
      await controller.userSignedIn(7);

      controller.userSignedOut();

      expect(controller.state.active, isFalse);
      expect(storage.seen, isEmpty);
    });

    test('can be restarted after it was seen', () async {
      storage.seen.add(7);
      await controller.userSignedIn(7);

      controller.restart();

      expect(controller.currentStep?.id, 'welcome');
    });
  });

  group('OnboardingOverlay', () {
    late _MemoryStorage storage;
    late _TestAuth auth;
    late GoRouter router;
    var otherTaps = 0;

    setUp(() {
      storage = _MemoryStorage();
      auth = _TestAuth();
      otherTaps = 0;
      router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: Column(
                children: [
                  const Spacer(),
                  OnboardingTarget(
                    id: 'go',
                    child: ElevatedButton(
                      onPressed: () => context.go('/next'),
                      child: const Text('Go'),
                    ),
                  ),
                  ElevatedButton(onPressed: () => otherTaps++, child: const Text('Other')),
                ],
              ),
            ),
          ),
          GoRoute(
            path: '/next',
            builder: (context, state) => const Scaffold(body: Text('next page')),
          ),
        ],
      );
    });

    Future<void> pumpApp(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider.overrideWith((ref) => auth),
            onboardingStorageProvider.overrideWithValue(storage),
            tourStepsProvider.overrideWithValue(_steps),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => OnboardingOverlay(router: router, child: child!),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> endTest(WidgetTester tester) async {
      // Unmounting stops the overlay's per-frame ticker.
      await tester.pumpWidget(const SizedBox());
    }

    testWidgets('walks a new account through the tour by letting them use the app', (tester) async {
      await pumpApp(tester);
      expect(find.text('Welcome'), findsNothing, reason: 'nobody is signed in yet');

      auth.signInAs(_signedIn);
      await tester.pump();
      await tester.pump();
      expect(find.text('Welcome'), findsOneWidget);

      await tester.tap(find.text('Start tour'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Press go'), findsOneWidget);

      // Modal: everything but the highlighted button is blocked...
      await tester.tap(find.text('Other'), warnIfMissed: false);
      expect(otherTaps, 0);
      expect(find.text('Press go'), findsOneWidget);

      // ...and the highlighted button is the real thing: it navigates, and
      // the tour moves on because the app did.
      await tester.tap(find.text('Go'));
      await tester.pump();
      await tester.pump();
      expect(find.text('next page'), findsOneWidget);
      expect(find.text('All set'), findsOneWidget);

      await tester.tap(find.text('Finish'));
      await tester.pump();
      expect(find.text('All set'), findsNothing);
      expect(storage.seen, {7});

      await endTest(tester);
    });

    testWidgets('"Skip tour" closes it for good', (tester) async {
      auth.signInAs(_signedIn);
      await pumpApp(tester);
      await tester.pump();
      expect(find.text('Welcome'), findsOneWidget);

      await tester.tap(find.text('Skip tour'));
      await tester.pump();

      expect(find.text('Welcome'), findsNothing);
      expect(storage.seen, {7});
      await endTest(tester);
    });

    testWidgets('a step whose target is not on screen does not lock the app', (tester) async {
      auth.signInAs(_signedIn);
      await pumpApp(tester);
      await tester.pump();
      await tester.tap(find.text('Start tour'));
      await tester.pump();
      router.go('/next'); // away from the page holding the 'go' target
      await tester.pump();
      await tester.pump();

      // Navigating there is what 'go' wanted anyway; the point is the
      // overlay is gone or non-blocking rather than a wall over the app.
      expect(find.text('next page'), findsOneWidget);
      await endTest(tester);
    });

    testWidgets('"Skip step" moves on without doing the thing', (tester) async {
      auth.signInAs(_signedIn);
      await pumpApp(tester);
      await tester.pump();
      await tester.tap(find.text('Start tour'));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Skip step'));
      await tester.pump();

      expect(find.text('All set'), findsOneWidget);
      await endTest(tester);
    });
  });
}
