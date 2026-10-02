import 'package:dinatos_frontend/features/activities/live/live_session.dart';
import 'package:dinatos_frontend/features/activities/live/live_workout_notification.dart';
import 'package:dinatos_frontend/features/home/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _RecordingService implements LiveWorkoutNotificationService {
  final shown = <LiveWorkoutNotificationContent>[];
  var cancelled = 0;

  @override
  Future<void> show(LiveWorkoutNotificationContent content) async => shown.add(content);

  @override
  Future<void> cancel() async => cancelled++;
}

GoRouter _router() => GoRouter(
  initialLocation: '/routines',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(navigationShell: shell),
      branches: [
        for (final path in ['/exercises', '/routines', '/activities', '/measurements', '/profile'])
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: path,
                builder: (context, state) => Scaffold(body: Text('page $path')),
                routes: [
                  if (path == '/activities')
                    GoRoute(
                      path: 'live',
                      builder: (context, state) => const Scaffold(body: Text('live screen')),
                    ),
                ],
              ),
            ],
          ),
      ],
    ),
  ],
);

void main() {
  testWidgets('banner shows on other tabs during a workout and returns to it on tap', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = _router();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    expect(find.text('Workout in progress'), findsNothing);

    container.read(liveActivityProvider.notifier).start();
    await tester.pump();
    expect(find.text('Workout in progress'), findsOneWidget);

    await tester.tap(find.text('Workout in progress'));
    await tester.pumpAndSettle();
    expect(find.text('live screen'), findsOneWidget);
    expect(find.text('Workout in progress'), findsNothing);

    container.read(liveActivityProvider.notifier).pauseClock();
    router.go('/profile');
    await tester.pumpAndSettle();
    expect(find.text('Workout paused'), findsOneWidget);

    container.read(liveActivityProvider.notifier).finish();
    await tester.pump();
    expect(find.text('Workout paused'), findsNothing);
  });

  test('notification follows the session: shown, updated, then cancelled', () {
    final service = _RecordingService();
    final container = ProviderContainer(
      overrides: [liveWorkoutNotificationServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    container.read(liveWorkoutNotificationSyncProvider);
    final notifier = container.read(liveActivityProvider.notifier);

    notifier.start();
    expect(service.shown, hasLength(1));
    expect(service.shown.last.pausedElapsed, isNull);

    notifier.addExercise(1);
    expect(service.shown, hasLength(2));
    expect(service.shown.last.exerciseCount, 1);

    notifier.pauseClock();
    expect(service.shown.last.pausedElapsed, isNotNull);

    notifier.finish();
    expect(service.cancelled, 1);
  });
}
