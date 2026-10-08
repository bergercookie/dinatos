import 'package:dinatos_frontend/core/server_url_provider.dart';
import 'package:dinatos_frontend/features/calendar/calendar_feed_screen.dart';
import 'package:dinatos_frontend/features/calendar/planned_workout_screen.dart';
import 'package:dinatos_frontend/features/calendar/planned_workouts_repository.dart';
import 'package:dinatos_frontend/features/calendar/upcoming_workouts_card.dart';
import 'package:dinatos_frontend/features/routines/routines_providers.dart';
import 'package:dinatos_frontend/models/planned_workout.dart';
import 'package:dinatos_frontend/models/routine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements PlannedWorkoutsRepository {}

class _FakePlan extends Fake implements PlannedWorkout {}

const _routine = Routine(id: 4, name: 'Push day');

Future<void> _pumpApp(
  WidgetTester tester,
  _MockRepository repository,
  Widget home, {
  List<Override> overrides = const [],
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => home),
      GoRoute(
        path: '/activities',
        builder: (context, state) => const Scaffold(body: Text('home screen')),
      ),
      GoRoute(
        path: '/activities/plan/new',
        builder: (context, state) => const Scaffold(body: Text('new plan screen')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        plannedWorkoutsRepositoryProvider.overrideWithValue(repository),
        routineListProvider.overrideWith((ref) async => [_routine]),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => registerFallbackValue(_FakePlan()));

  group('PlannedWorkoutScreen', () {
    testWidgets('schedules a routine for the chosen day, defaulting its title from the routine', (
      tester,
    ) async {
      final repository = _MockRepository();
      when(() => repository.create(any())).thenAnswer((i) async => i.positionalArguments[0]);
      when(() => repository.list()).thenAnswer((_) async => []);
      await _pumpApp(tester, repository, PlannedWorkoutScreen(initialDate: DateTime(2030, 5, 20)));

      await tester.tap(find.byType(DropdownButtonFormField<int?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Push day').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Schedule'));
      await tester.pumpAndSettle();

      final saved = verify(() => repository.create(captureAny())).captured.single as PlannedWorkout;
      expect(saved.routineId, 4);
      expect(saved.title, 'Push day');
      expect(saved.scheduledAt, DateTime(2030, 5, 20, 18));
      expect(saved.durationMinutes, 60);
      expect(saved.reminderMinutes, 30);
      expect(find.text('home screen'), findsOneWidget);
    });

    testWidgets('needs a title or a routine', (tester) async {
      final repository = _MockRepository();
      await _pumpApp(tester, repository, const PlannedWorkoutScreen());

      await tester.tap(find.text('Schedule'));
      await tester.pumpAndSettle();

      expect(find.text('Give it a title, or pick a routine.'), findsOneWidget);
      verifyNever(() => repository.create(any()));
    });

    testWidgets('editing an existing plan replaces it, and it can be removed', (tester) async {
      final repository = _MockRepository();
      final plan = PlannedWorkout(
        id: 5,
        title: 'Legs',
        scheduledAt: DateTime(2030, 5, 20, 7, 30),
        reminderMinutes: null,
        durationMinutes: 90,
      );
      when(() => repository.get(5)).thenAnswer((_) async => plan);
      when(() => repository.replace(5, any())).thenAnswer((i) async => i.positionalArguments[1]);
      when(() => repository.delete(5)).thenAnswer((_) async {});
      when(() => repository.list()).thenAnswer((_) async => []);
      await _pumpApp(tester, repository, const PlannedWorkoutScreen(plannedId: 5));

      expect(find.widgetWithText(TextField, 'Legs'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Legs'), 'Leg day');
      await tester.scrollUntilVisible(
        find.text('Save changes'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      final replaced =
          verify(() => repository.replace(5, captureAny())).captured.single as PlannedWorkout;
      expect(replaced.title, 'Leg day');
      expect(replaced.reminderMinutes, isNull);
      expect(replaced.durationMinutes, 90);
      expect(replaced.scheduledAt, DateTime(2030, 5, 20, 7, 30));

      // Back on a fresh screen: delete asks first.
      await _pumpApp(tester, repository, const PlannedWorkoutScreen(plannedId: 5));
      await tester.tap(find.byTooltip('Remove from calendar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      verify(() => repository.delete(5)).called(1);
    });
  });

  group('UpcomingWorkoutsCard', () {
    final now = DateTime(2030, 5, 10, 12);

    testWidgets('invites scheduling when nothing is planned', (tester) async {
      await _pumpApp(
        tester,
        _MockRepository(),
        Scaffold(
          body: UpcomingWorkoutsCard(plans: const [], now: now),
        ),
      );

      expect(find.textContaining('Nothing planned'), findsOneWidget);
      await tester.tap(find.text('Schedule'));
      await tester.pumpAndSettle();
      expect(find.text('new plan screen'), findsOneWidget);
    });

    testWidgets('lists the next plans and offers Start only on one due today', (tester) async {
      final plans = [
        PlannedWorkout(id: 1, title: 'Today plan', scheduledAt: DateTime(2030, 5, 10, 18)),
        PlannedWorkout(id: 2, title: 'Later plan', scheduledAt: DateTime(2030, 5, 12, 18)),
        PlannedWorkout(
          id: 3,
          title: 'Done plan',
          scheduledAt: DateTime(2030, 5, 11, 18),
          completedActivityId: 1,
        ),
      ];
      await _pumpApp(
        tester,
        _MockRepository(),
        Scaffold(
          body: UpcomingWorkoutsCard(plans: plans, now: now),
        ),
      );

      expect(find.text('Today plan'), findsOneWidget);
      expect(find.text('Later plan'), findsOneWidget);
      expect(find.text('Done plan'), findsNothing);
      expect(find.byTooltip('Start Today plan'), findsOneWidget);
      expect(find.byTooltip('Start Later plan'), findsNothing);
    });
  });

  group('CalendarFeedScreen', () {
    Future<_MockRepository> pump(WidgetTester tester, CalendarFeed initial) async {
      final repository = _MockRepository();
      var current = initial;
      when(() => repository.feed()).thenAnswer((_) async => current);
      when(() => repository.enableFeed()).thenAnswer((_) async {
        return current = const CalendarFeed(token: 'new', path: '/calendar/new.ics');
      });
      when(() => repository.disableFeed()).thenAnswer((_) async {
        current = const CalendarFeed();
      });
      await _pumpApp(
        tester,
        repository,
        const CalendarFeedScreen(),
        overrides: [serverUrlProvider.overrideWith((ref) => 'https://dinatos.example/')],
      );
      return repository;
    }

    test('builds the URL without doubling the slash', () {
      expect(
        calendarFeedUrl('https://x.test/', '/calendar/t.ics'),
        'https://x.test/calendar/t.ics',
      );
      expect(calendarFeedUrl('https://x.test', '/calendar/t.ics'), 'https://x.test/calendar/t.ics');
    });

    testWidgets('is off until a link is created, then shows the full link', (tester) async {
      final repository = await pump(tester, const CalendarFeed());

      expect(find.text('Create calendar link'), findsOneWidget);
      await tester.tap(find.text('Create calendar link'));
      await tester.pumpAndSettle();

      verify(() => repository.enableFeed()).called(1);
      expect(find.text('https://dinatos.example/calendar/new.ics'), findsOneWidget);
    });

    testWidgets('an existing link can be copied, replaced after confirming, and turned off', (
      tester,
    ) async {
      final repository = await pump(
        tester,
        const CalendarFeed(token: 'abc', path: '/calendar/abc.ics'),
      );
      expect(find.text('https://dinatos.example/calendar/abc.ics'), findsOneWidget);

      final copied = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String?);
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();
      expect(find.text('Link copied'), findsOneWidget);
      expect(copied, ['https://dinatos.example/calendar/abc.ics']);

      await tester.tap(find.text('Create a new link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      verify(() => repository.enableFeed()).called(1);
      expect(find.text('https://dinatos.example/calendar/new.ics'), findsOneWidget);

      await tester.tap(find.text('Turn the feed off'));
      await tester.pumpAndSettle();
      verify(() => repository.disableFeed()).called(1);
      expect(find.text('Create calendar link'), findsOneWidget);
    });
  });
}
