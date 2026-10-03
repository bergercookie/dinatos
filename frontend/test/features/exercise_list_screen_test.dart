import 'package:dinatos_frontend/core/dio_provider.dart';
import 'package:dinatos_frontend/features/exercises/exercise_list_screen.dart';
import 'package:dinatos_frontend/features/exercises/exercises_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fakes.dart';

Map<String, dynamic> _exercise(int id, String name) => {
  'id': id,
  'name': name,
  'tracks_weight': true,
  'tracks_reps': true,
  'tracks_distance': false,
  'tracks_duration': false,
  'is_custom': true,
};

Response<List<dynamic>> _page(List<Map<String, dynamic>> items, int total) => Response(
  requestOptions: RequestOptions(path: '/exercises'),
  statusCode: 200,
  data: items,
  headers: Headers.fromMap({
    'x-total-count': [total.toString()],
  }),
);

/// Stubs `GET /exercises` for every `limit`/`offset`/`search` combination the
/// screen might request, dispatching to [pages] by `(search, offset)` so
/// each test only has to describe what each page of results actually is.
void _stubPages(MockDio dio, Map<(String?, int), List<Map<String, dynamic>>> pages, int total) {
  when(() => dio.get<List<dynamic>>('/exercises', queryParameters: any(named: 'queryParameters')))
      .thenAnswer((invocation) async {
        final params = invocation.namedArguments[#queryParameters] as Map;
        final search = params['search'] as String?;
        final offset = params['offset'] as int;
        final items = pages[(search, offset)] ?? [];
        return _page(items, total);
      });
}

void main() {
  testWidgets('loads the first page and fetches the next one on scroll', (tester) async {
    final dio = MockDio();
    final firstPage = List.generate(
      exercisePageSize,
      (i) => _exercise(i, 'Exercise ${i.toString().padLeft(3, '0')}'),
    );
    final secondPage = [_exercise(999, 'Last Exercise')];
    _stubPages(dio, {
      (null, 0): firstPage,
      (null, exercisePageSize): secondPage,
    }, exercisePageSize + 1);

    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ExerciseListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Exercise 000'), findsOneWidget);
    expect(find.text('Last Exercise'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -100000));
    await tester.pumpAndSettle();

    expect(find.text('Last Exercise'), findsOneWidget);
  });

  testWidgets('debounces the search box instead of refetching on every keystroke', (tester) async {
    final dio = MockDio();
    _stubPages(dio, {
      (null, 0): [_exercise(1, 'Squat')],
      ('bench', 0): [_exercise(2, 'Bench Press')],
    }, 1);

    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ExerciseListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Squat'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bench');
    await tester.pump(const Duration(milliseconds: 100));
    // Still well within the debounce window -- no refetch, and the old
    // results are still on screen.
    expect(find.text('Squat'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Squat'), findsNothing);
  });

  testWidgets('the source chips ask the backend for only custom or only built-in exercises', (
    tester,
  ) async {
    final dio = MockDio();
    final requested = <Object?>[];
    when(() => dio.get<List<dynamic>>('/exercises', queryParameters: any(named: 'queryParameters')))
        .thenAnswer((invocation) async {
          final params = invocation.namedArguments[#queryParameters] as Map;
          requested.add(params['is_custom']);
          return switch (params['is_custom']) {
            true => _page([_exercise(2, 'My Lift')], 1),
            _ => _page([_exercise(1, 'Squat'), _exercise(2, 'My Lift')], 2),
          };
        });

    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ExerciseListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Squat'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Custom'));
    await tester.pumpAndSettle();

    expect(requested.last, true);
    expect(find.text('Squat'), findsNothing);
    expect(find.text('My Lift'), findsOneWidget);
  });

  testWidgets('each exercise has a progress button that opens its progress page', (tester) async {
    final dio = MockDio();
    _stubPages(dio, {
      (null, 0): [_exercise(7, 'Squat')],
    }, 1);
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const ExerciseListScreen()),
        GoRoute(
          path: '/exercises/:id/progress',
          builder: (context, state) => Text('progress of ${state.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    // The tutorial button is still there beside it.
    expect(find.byTooltip('View tutorial'), findsOneWidget);

    await tester.tap(find.byTooltip('View progress'));
    await tester.pumpAndSettle();

    expect(find.text('progress of 7'), findsOneWidget);
  });
}
