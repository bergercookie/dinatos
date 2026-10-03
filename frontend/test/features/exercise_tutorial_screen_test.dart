import 'package:dinatos_frontend/core/dio_provider.dart';
import 'package:dinatos_frontend/features/exercises/exercise_tutorial_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fakes.dart';

IconButton _iconButton(WidgetTester tester, String tooltip) => tester.widget<IconButton>(
  find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton)),
);

Map<String, dynamic> _exerciseJson(int id, String name) => {
  'id': id,
  'name': name,
  'tracks_weight': true,
  'tracks_reps': true,
  'tracks_distance': false,
  'tracks_duration': false,
  'is_custom': false,
};

Response<Map<String, dynamic>> _exerciseResponse(int id, String name) => Response(
  requestOptions: RequestOptions(path: '/exercises/$id'),
  statusCode: 200,
  data: _exerciseJson(id, name),
);

/// A [MockDio] whose catalog (`GET /exercises`) holds three exercises, in
/// order, plus per-exercise `GET`s and a 404 tutorial for each -- everything
/// [ExerciseTutorialScreen]'s next/previous navigation needs, without caring
/// what the tutorial content itself looks like.
MockDio _catalogDio({
  List<(int, String)> exercises = const [(1, 'Alpha'), (2, 'Beta'), (3, 'Gamma')],
}) {
  final dio = MockDio();
  when(() => dio.get<List<dynamic>>('/exercises', queryParameters: any(named: 'queryParameters')))
      .thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/exercises'),
          statusCode: 200,
          data: [for (final (id, name) in exercises) _exerciseJson(id, name)],
        ),
      );
  for (final (id, name) in exercises) {
    when(() => dio.get<Map<String, dynamic>>('/exercises/$id'))
        .thenAnswer((_) async => _exerciseResponse(id, name));
    when(() => dio.get<Map<String, dynamic>>('/exercises/$id/tutorial')).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/exercises/$id/tutorial'),
        response: Response(
          requestOptions: RequestOptions(path: '/exercises/$id/tutorial'),
          statusCode: 404,
        ),
      ),
    );
  }
  return dio;
}

/// A minimal router that only knows the tutorial route, so `context.go` in
/// the screen itself has somewhere real to navigate to.
GoRouter _tutorialRouter({required int initialId}) => GoRouter(
  initialLocation: '/exercises/$initialId/tutorial',
  routes: [
    GoRoute(
      path: '/exercises/:id/tutorial',
      builder: (context, state) =>
          ExerciseTutorialScreen(exerciseId: int.parse(state.pathParameters['id']!)),
    ),
  ],
);

void main() {
  testWidgets('fetches a backend-proxied GIF path through Dio, not Image.network', (tester) async {
    final dio = MockDio();
    when(() => dio.get<Map<String, dynamic>>('/exercises/1'))
        .thenAnswer((_) async => _exerciseResponse(1, 'Bench Press'));
    when(() => dio.get<Map<String, dynamic>>('/exercises/1/tutorial')).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/exercises/1/tutorial'),
        statusCode: 200,
        data: {
          'source': 'workoutx',
          'gif_urls': ['/exercises/media/workoutx/0025.gif'],
          'instructions': <String>[],
          'equipment': null,
          'primary_muscles': <String>[],
          'secondary_muscles': <String>[],
        },
      ),
    );
    when(
      () =>
          dio.get<List<int>>('/exercises/media/workoutx/0025.gif', options: any(named: 'options')),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/exercises/media/workoutx/0025.gif'),
        statusCode: 200,
        data: <int>[1, 2, 3],
      ),
    );
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ExerciseTutorialScreen(exerciseId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    verify(
      () =>
          dio.get<List<int>>('/exercises/media/workoutx/0025.gif', options: any(named: 'options')),
    ).called(1);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('shows the GIF, muscles, and instructions when a tutorial exists', (tester) async {
    final dio = MockDio();
    when(() => dio.get<Map<String, dynamic>>('/exercises/1'))
        .thenAnswer((_) async => _exerciseResponse(1, '3/4 Sit-Up'));
    when(() => dio.get<Map<String, dynamic>>('/exercises/1/tutorial')).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/exercises/1/tutorial'),
        statusCode: 200,
        data: {
          'source': 'free_exercise_db',
          'gif_urls': <String>[],
          'instructions': ['Lie down.', 'Sit up.'],
          'equipment': 'body only',
          'primary_muscles': ['abdominals'],
          'secondary_muscles': <String>[],
        },
      ),
    );
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ExerciseTutorialScreen(exerciseId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3/4 Sit-Up'), findsOneWidget); // the AppBar title
    expect(find.text('body only'), findsOneWidget);
    expect(find.text('abdominals'), findsOneWidget);
    expect(find.textContaining('Lie down.'), findsOneWidget);
    expect(find.textContaining('Sit up.'), findsOneWidget);
  });

  Future<void> pumpTwoFrameTutorial(WidgetTester tester, {bool reduceMotion = false}) async {
    final dio = MockDio();
    when(() => dio.get<Map<String, dynamic>>('/exercises/1'))
        .thenAnswer((_) async => _exerciseResponse(1, '3/4 Sit-Up'));
    when(() => dio.get<Map<String, dynamic>>('/exercises/1/tutorial')).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/exercises/1/tutorial'),
        statusCode: 200,
        data: {
          'source': 'free_exercise_db',
          'gif_urls': ['https://example.test/0.jpg', 'https://example.test/1.jpg'],
          'instructions': <String>[],
          'equipment': null,
          'primary_muscles': <String>[],
          'secondary_muscles': <String>[],
        },
      ),
    );
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: const MaterialApp(home: ExerciseTutorialScreen(exerciseId: 1)),
        ),
      ),
    );
    // Not `pumpAndSettle`: the carousel's periodic timer never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('alternates start/end frames, and a tap pauses and resumes', (tester) async {
    await pumpTwoFrameTutorial(tester);
    expect(find.text('Start'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 850));
    expect(find.text('End'), findsOneWidget);

    await tester.tap(find.text('End'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('End'), findsOneWidget); // paused: no longer advancing

    await tester.tap(find.text('End'));
    await tester.pump(const Duration(milliseconds: 850));
    expect(find.text('Start'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // unmount: cancels the timer
  });

  testWidgets('with reduced motion it never auto-plays; a tap steps to the next frame', (
    tester,
  ) async {
    await pumpTwoFrameTutorial(tester, reduceMotion: true);
    expect(find.text('Start'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Start'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('End'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('names the tutorial source, with a tooltip explaining it', (tester) async {
    final dio = MockDio();
    when(() => dio.get<Map<String, dynamic>>('/exercises/1'))
        .thenAnswer((_) async => _exerciseResponse(1, '3/4 Sit-Up'));
    when(() => dio.get<Map<String, dynamic>>('/exercises/1/tutorial')).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/exercises/1/tutorial'),
        statusCode: 200,
        data: {
          'source': 'workoutx',
          'gif_urls': <String>[],
          'instructions': <String>[],
          'equipment': null,
          'primary_muscles': <String>[],
          'secondary_muscles': <String>[],
        },
      ),
    );
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ExerciseTutorialScreen(exerciseId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Source: WorkoutX'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.help_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('workoutxapp.com'), findsOneWidget);
  });

  testWidgets('shows a clean empty state instead of an error when nothing is available', (
    tester,
  ) async {
    // Exactly what ExercisesRepository.getTutorial does with the
    // backend's 404 -- see its own doc comment: an expected outcome for
    // a person's own custom exercise, not a failure.
    final dio = MockDio();
    when(() => dio.get<Map<String, dynamic>>('/exercises/2'))
        .thenAnswer((_) async => _exerciseResponse(2, 'My Custom Move'));
    when(() => dio.get<Map<String, dynamic>>('/exercises/2/tutorial')).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/exercises/2/tutorial'),
        response: Response(
          requestOptions: RequestOptions(path: '/exercises/2/tutorial'),
          statusCode: 404,
        ),
      ),
    );
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ExerciseTutorialScreen(exerciseId: 2)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('My Custom Move'), findsOneWidget);
    expect(find.text('No tutorial available for this exercise.'), findsOneWidget);
  });

  testWidgets('the next/previous buttons step through the catalog and disable at its ends', (
    tester,
  ) async {
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(_catalogDio())]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: _tutorialRouter(initialId: 2)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Beta'), findsOneWidget); // the AppBar title

    await tester.tap(find.byTooltip('Next exercise'));
    await tester.pumpAndSettle();
    expect(find.text('Gamma'), findsOneWidget);
    expect(_iconButton(tester, 'Next exercise').onPressed, isNull);

    await tester.tap(find.byTooltip('Previous exercise'));
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous exercise'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(_iconButton(tester, 'Previous exercise').onPressed, isNull);
  });

  testWidgets('the left/right arrow keys step through the catalog', (tester) async {
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(_catalogDio())]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: _tutorialRouter(initialId: 2)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Gamma'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('a horizontal swipe steps through the catalog', (tester) async {
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(_catalogDio())]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: _tutorialRouter(initialId: 2)),
      ),
    );
    await tester.pumpAndSettle();

    final body = find.text('No tutorial available for this exercise.');

    // A swipe left (finger moving left, negative dx) advances to the next
    // exercise, the same direction as flipping to the next photo.
    await tester.fling(body, const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Gamma'), findsOneWidget);

    // A swipe right goes back to the previous one.
    await tester.fling(body, const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsOneWidget);
  });
}
