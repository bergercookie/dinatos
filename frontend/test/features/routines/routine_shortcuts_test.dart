import 'dart:async';

import 'package:dinatos_frontend/core/auth/auth_state.dart';
import 'package:dinatos_frontend/core/router.dart';
import 'package:dinatos_frontend/features/routines/routine_shortcuts.dart';
import 'package:dinatos_frontend/models/user.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A [RoutineShortcutService] the tests drive by hand.
class FakeRoutineShortcutService implements RoutineShortcutService {
  FakeRoutineShortcutService({this.initial, this.supported = true});

  int? initial;
  final bool supported;
  final launches = StreamController<int>.broadcast();

  @override
  bool get isSupported => supported;

  @override
  Future<bool> pin({required int routineId, required String name}) async => true;

  @override
  Future<int?> initialRoutineId() async => initial;

  @override
  Stream<int> get routineLaunches => launches.stream;
}

const _channel = MethodChannel(routineShortcutsChannelName);
const _signedIn = AuthAuthenticated(
  token: 't',
  user: User(id: 1, email: 'a@example.com', isAdmin: false),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  group('AndroidRoutineShortcutService', () {
    test('pin sends the routine id and name and reports the launcher answer', () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        seen = call;
        return true;
      });

      final pinned = await AndroidRoutineShortcutService().pin(routineId: 7, name: 'Push day');

      expect(pinned, isTrue);
      expect(seen!.method, pinShortcutMethod);
      expect(seen!.arguments, {'routineId': 7, 'name': 'Push day'});
    });

    test('pin is false when the launcher cannot pin', () async {
      messenger.setMockMethodCallHandler(_channel, (call) async => false);
      expect(await AndroidRoutineShortcutService().pin(routineId: 7, name: 'x'), isFalse);
    });

    test('pin is false when the platform returns nothing', () async {
      messenger.setMockMethodCallHandler(_channel, (call) async => null);
      expect(await AndroidRoutineShortcutService().pin(routineId: 7, name: 'x'), isFalse);
    });

    test('a platform error becomes a ShortcutException', () async {
      messenger.setMockMethodCallHandler(_channel, (call) async {
        throw PlatformException(code: 'bad_arguments', message: 'routineId and name are required');
      });

      await expectLater(
        AndroidRoutineShortcutService().pin(routineId: 7, name: 'x'),
        throwsA(isA<ShortcutException>().having((e) => e.message, 'message', contains('required'))),
      );
    });

    test('a platform error without a message still has a readable one', () async {
      messenger.setMockMethodCallHandler(_channel, (call) async {
        throw PlatformException(code: 'boom');
      });

      await expectLater(
        AndroidRoutineShortcutService().pin(routineId: 7, name: 'x'),
        throwsA(isA<ShortcutException>().having((e) => e.toString(), 'text', contains('Could'))),
      );
    });

    test('initialRoutineId returns the routine of a cold-start shortcut launch', () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        seen = call;
        return 12;
      });

      expect(await AndroidRoutineShortcutService().initialRoutineId(), 12);
      expect(seen!.method, initialRoutineIdMethod);
    });

    test(
      'with no native side listening, pin fails readably and initialRoutineId is null',
      () async {
        // No mock handler: the channel has no listener, as in a build without the bridge.
        final service = AndroidRoutineShortcutService();

        await expectLater(
          service.pin(routineId: 7, name: 'x'),
          throwsA(
            isA<ShortcutException>().having((e) => e.message, 'message', contains('not available')),
          ),
        );
        expect(await service.initialRoutineId(), isNull);
      },
    );

    test('initialRoutineId is null for a normal launch, or when the call fails', () async {
      messenger.setMockMethodCallHandler(_channel, (call) async => null);
      expect(await AndroidRoutineShortcutService().initialRoutineId(), isNull);

      messenger.setMockMethodCallHandler(_channel, (call) async {
        throw PlatformException(code: 'boom');
      });
      expect(await AndroidRoutineShortcutService().initialRoutineId(), isNull);
    });

    test('a tapped shortcut while running arrives on the launches stream', () async {
      final service = AndroidRoutineShortcutService();
      final received = <int>[];
      final subscription = service.routineLaunches.listen(received.add);
      addTearDown(subscription.cancel);

      Future<void> fromAndroid(String method, Object? argument) async {
        await messenger.handlePlatformMessage(
          routineShortcutsChannelName,
          const StandardMethodCodec().encodeMethodCall(MethodCall(method, argument)),
          (_) {},
        );
      }

      await fromAndroid(routineLaunchedMethod, 5);
      await fromAndroid(routineLaunchedMethod, 9);
      // Not ours, or malformed: ignored.
      await fromAndroid('somethingElse', 3);
      await fromAndroid(routineLaunchedMethod, 'not an int');
      await pumpEventQueue();

      expect(received, [5, 9]);
    });

    test('it reports shortcuts as supported', () {
      expect(AndroidRoutineShortcutService().isSupported, isTrue);
    });
  });

  group('NoopRoutineShortcutService', () {
    test('is unsupported and never launches anything', () async {
      final service = NoopRoutineShortcutService();
      expect(service.isSupported, isFalse);
      expect(await service.pin(routineId: 1, name: 'x'), isFalse);
      expect(await service.initialRoutineId(), isNull);
      expect(await service.routineLaunches.isEmpty, isTrue);
    });
  });

  group('routineShortcutServiceProvider', () {
    test('is the Android service on Android (the flutter_test default platform)', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(routineShortcutServiceProvider).isSupported, isTrue);
    });

    for (final platform in [
      TargetPlatform.iOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.macOS,
    ]) {
      test('is the no-op service on $platform', () {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final container = ProviderContainer();
        addTearDown(container.dispose);
        expect(container.read(routineShortcutServiceProvider).isSupported, isFalse);
      });
    }
  });

  group('routineShortcutLaunchProvider', () {
    late StateProvider<AuthState> auth;
    late FakeRoutineShortcutService service;
    late GoRouter router;
    late ProviderContainer container;

    Future<void> pump(WidgetTester tester, {AuthState state = _signedIn, int? initial}) async {
      auth = StateProvider<AuthState>((ref) => state);
      service = FakeRoutineShortcutService(initial: initial);
      addTearDown(service.launches.close);
      router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: Text('home')),
          ),
          GoRoute(
            path: '/routines/:id/start',
            builder: (context, state) =>
                Scaffold(body: Text('start ${state.pathParameters['id']}')),
          ),
        ],
      );
      addTearDown(router.dispose);
      container = ProviderContainer(
        overrides: [
          routineShortcutServiceProvider.overrideWithValue(service),
          shortcutAuthProvider.overrideWith((ref) => ref.watch(auth)),
          routerProvider.overrideWithValue(router),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              ref.watch(routineShortcutLaunchProvider);
              return MaterialApp.router(routerConfig: router);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a normal launch goes nowhere', (tester) async {
      await pump(tester);
      expect(find.text('home'), findsOneWidget);
      expect(container.read(pendingRoutineLaunchProvider), isNull);
    });

    testWidgets('a cold start from a shortcut opens the routine start screen', (tester) async {
      await pump(tester, initial: 7);
      expect(find.text('start 7'), findsOneWidget);
      expect(container.read(pendingRoutineLaunchProvider), isNull);
    });

    testWidgets('a shortcut tapped while running opens it too', (tester) async {
      await pump(tester);

      service.launches.add(3);
      await tester.pumpAndSettle();

      expect(find.text('start 3'), findsOneWidget);
    });

    testWidgets('signed out, it waits for the login and then starts', (tester) async {
      await pump(tester, state: const AuthUnauthenticated(), initial: 7);

      expect(find.text('home'), findsOneWidget);
      expect(container.read(pendingRoutineLaunchProvider), 7);

      container.read(auth.notifier).state = _signedIn;
      await tester.pumpAndSettle();

      expect(find.text('start 7'), findsOneWidget);
      expect(container.read(pendingRoutineLaunchProvider), isNull);
    });

    testWidgets('while the login is still being checked it waits too', (tester) async {
      await pump(tester, state: const AuthUnknown(), initial: 7);
      expect(find.text('home'), findsOneWidget);

      container.read(auth.notifier).state = _signedIn;
      await tester.pumpAndSettle();

      expect(find.text('start 7'), findsOneWidget);
    });

    testWidgets('a launch is acted on once: a later login change does not repeat it', (
      tester,
    ) async {
      await pump(tester, initial: 7);
      expect(find.text('start 7'), findsOneWidget);
      router.go('/');
      await tester.pumpAndSettle();

      container.read(auth.notifier).state = const AuthUnauthenticated();
      await tester.pumpAndSettle();
      container.read(auth.notifier).state = _signedIn;
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('the newest of two quick taps wins', (tester) async {
      await pump(tester, state: const AuthUnauthenticated());

      service.launches
        ..add(1)
        ..add(2);
      await tester.pump();
      container.read(auth.notifier).state = _signedIn;
      await tester.pumpAndSettle();

      expect(find.text('start 2'), findsOneWidget);
    });
  });
}
