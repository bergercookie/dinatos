import 'dart:async';

import 'package:dinatos_frontend/core/dio_provider.dart';
import 'package:dinatos_frontend/features/routines/routine_form_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fakes.dart';

Response<T> _ok<T>(String path, T data) => Response(
  requestOptions: RequestOptions(path: path),
  statusCode: 200,
  data: data,
);

Map<String, dynamic> _exercise(int id, String name) => {
  'id': id,
  'name': name,
  'tracks_weight': true,
  'tracks_reps': true,
  'tracks_distance': false,
  'tracks_duration': false,
  'is_custom': true,
  'equipment': null,
  'primary_muscles': <String>[],
  'secondary_muscles': <String>[],
};

Map<String, dynamic> _routineExercise(int id, int exerciseId, {int? group}) => {
  'id': id,
  'position': id,
  'exercise_id': exerciseId,
  'superset_group': group,
  'notes': null,
  'sets': <dynamic>[],
};

/// An existing routine of three exercises -- Bench (1), Row (2), Curl (3) --
/// the first two already a superset when [grouped].
Future<MockDio> _pump(WidgetTester tester, {bool grouped = false}) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dio = buildMockDio();
  when(() => dio.get<List<dynamic>>('/exercises', queryParameters: any(named: 'queryParameters')))
      .thenAnswer(
        (_) async => _ok<List<dynamic>>('/exercises', [
          _exercise(1, 'Bench Press'),
          _exercise(2, 'Row'),
          _exercise(3, 'Curl'),
        ]),
      );
  when(() => dio.get<Map<String, dynamic>>('/routines/7')).thenAnswer(
    (_) async => _ok<Map<String, dynamic>>('/routines/7', {
      'id': 7,
      'name': 'Upper',
      'description': null,
      'exercises': [
        _routineExercise(1, 1, group: grouped ? 4 : null),
        _routineExercise(2, 2, group: grouped ? 4 : null),
        _routineExercise(3, 3),
      ],
    }),
  );
  when(() => dio.put<Map<String, dynamic>>('/routines/7', data: any(named: 'data'))).thenAnswer(
    (_) async => _ok<Map<String, dynamic>>('/routines/7', {
      'id': 7,
      'name': 'Upper',
      'description': null,
      'exercises': <dynamic>[],
    }),
  );
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('routines')),
      ),
      GoRoute(path: '/edit', builder: (context, state) => const RoutineFormScreen(routineId: 7)),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  // Pushed, so that saving (which pops back) has somewhere to go.
  unawaited(router.push<void>('/edit'));
  await tester.pumpAndSettle();
  return dio;
}

Future<void> _menu(WidgetTester tester, int card, String entry) async {
  await tester.tap(find.byTooltip('Exercise options').at(card));
  await tester.pumpAndSettle();
  await tester.tap(find.text(entry));
  await tester.pumpAndSettle();
}

List<String> _names(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    if (const {'Bench Press', 'Row', 'Curl'}.contains(t.data)) t.data!,
];

List<dynamic> _savedExercises(MockDio dio) {
  final body =
      verify(() => dio.put<Map<String, dynamic>>('/routines/7', data: captureAny(named: 'data')))
              .captured
              .single
          as Map<String, dynamic>;
  return body['exercises'] as List<dynamic>;
}

void main() {
  testWidgets('the description box is roomy and grows with what is typed', (tester) async {
    await _pump(tester);
    final field = find.widgetWithText(TextField, 'Description (optional)');
    final empty = tester.getSize(field).height;
    expect(empty, greaterThan(90)); // four lines, not two

    await tester.enterText(field, List.generate(12, (i) => 'line $i').join('\n'));
    await tester.pump();
    expect(tester.getSize(field).height, greaterThan(empty));
  });

  testWidgets('linking exercises makes a superset that is saved with the routine', (tester) async {
    final dio = await _pump(tester);
    expect(find.textContaining('Superset'), findsNothing);

    await _menu(tester, 1, 'Superset with next exercise');
    expect(find.text('Superset A'), findsNWidgets(2));

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = _savedExercises(dio);
    expect(saved.map((e) => (e as Map)['exercise_id']), [1, 2, 3]);
    expect(saved.map((e) => (e as Map)['superset_group']), [null, 1, 1]);
  });

  testWidgets('an existing superset is shown, and leaving it dissolves a pair', (tester) async {
    final dio = await _pump(tester, grouped: true);
    expect(find.text('Superset A'), findsNWidgets(2));

    await _menu(tester, 0, 'Remove from superset');
    expect(find.textContaining('Superset'), findsNothing);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(_savedExercises(dio).map((e) => (e as Map)['superset_group']), [null, null, null]);
  });

  testWidgets('moving an exercise reorders the routine', (tester) async {
    final dio = await _pump(tester);
    expect(_names(tester), ['Bench Press', 'Row', 'Curl']);

    await _menu(tester, 2, 'Move up');
    expect(_names(tester), ['Bench Press', 'Curl', 'Row']);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(_savedExercises(dio).map((e) => (e as Map)['exercise_id']), [1, 3, 2]);
  });

  testWidgets('removing a member of a pair leaves the other one on its own', (tester) async {
    await _pump(tester, grouped: true);

    await tester.tap(find.byTooltip('Remove exercise').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Superset'), findsNothing);
    expect(_names(tester), ['Row', 'Curl']);
  });

  testWidgets('a set removed from the middle takes its own values with it', (tester) async {
    await _pump(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Add set').first);
      await tester.pumpAndSettle();
    }
    for (final (i, kg) in ['10', '20', '30'].indexed) {
      await tester.enterText(find.widgetWithText(TextFormField, 'kg').at(i), kg);
    }
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove set').at(0));
    await tester.pumpAndSettle();

    final shown = [
      for (var i = 0; i < 2; i++)
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.widgetWithText(TextFormField, 'kg').at(i),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
    ];
    expect(shown, ['20', '30']);
  });
}
