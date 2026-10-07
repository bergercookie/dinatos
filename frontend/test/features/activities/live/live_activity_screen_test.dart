import 'package:dinatos_frontend/core/dio_provider.dart';
import 'package:dinatos_frontend/features/activities/live/live_activity_screen.dart';
import 'package:dinatos_frontend/features/activities/live/speech_input.dart';
import 'package:dinatos_frontend/features/activities/live/live_session.dart';
import 'package:dinatos_frontend/models/routine.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/fakes.dart';

Response<T> _ok<T>(String path, T data) => Response(
  requestOptions: RequestOptions(path: path),
  statusCode: 200,
  data: data,
);

DioException _offline() => DioException(
  requestOptions: RequestOptions(path: '/'),
  type: DioExceptionType.connectionError,
);

Map<String, dynamic> _exercise(int id, String name, {String? equipment = 'barbell'}) => {
  'id': id,
  'name': name,
  'tracks_weight': true,
  'tracks_reps': true,
  'tracks_distance': false,
  'tracks_duration': false,
  'is_custom': true,
  'equipment': equipment,
  'primary_muscles': <String>[],
  'secondary_muscles': <String>[],
};

Map<String, dynamic> _historySet(double? kg, int reps, {String type = 'normal'}) => {
  'set_type': type,
  'weight_kg': kg,
  'reps': reps,
  'distance_km': null,
  'duration_seconds': null,
};

/// A server with a Bench Press (1) and a Row (2); Bench has a past session of
/// 3 x 8 @ 60 kg and an all-time best weight of 80 kg.
MockDio _dio({bool historyOffline = false}) {
  final dio = buildMockDio();
  when(() => dio.get<List<dynamic>>('/exercises', queryParameters: any(named: 'queryParameters')))
      .thenAnswer(
        (_) async =>
            _ok<List<dynamic>>('/exercises', [_exercise(1, 'Bench Press'), _exercise(2, 'Row')]),
      );
  for (final id in [1, 2]) {
    if (historyOffline) {
      when(
        () => dio.get<List<dynamic>>(
          '/exercises/$id/history',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenThrow(_offline());
      when(() => dio.get<Map<String, dynamic>>('/exercises/$id/records')).thenThrow(_offline());
      continue;
    }
    when(
      () => dio.get<List<dynamic>>(
        '/exercises/$id/history',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => _ok<List<dynamic>>(
        '/exercises/$id/history',
        id == 1
            ? [
                {
                  'activity_id': 4,
                  'activity_title': 'Push',
                  'started_at': '2026-09-01T10:00:00Z',
                  'sets': [_historySet(60, 8), _historySet(60, 8), _historySet(60, 8)],
                },
              ]
            : <dynamic>[],
      ),
    );
    when(() => dio.get<Map<String, dynamic>>('/exercises/$id/records')).thenAnswer(
      (_) async => _ok<Map<String, dynamic>>(
        '/exercises/$id/records',
        id == 1
            ? {'max_weight_kg': 80.0, 'max_reps': 12}
            : {'max_weight_kg': null, 'max_reps': null},
      ),
    );
  }
  return dio;
}

/// Typing only: the real one would touch the microphone plugin.
class _NoSpeech implements SpeechInput {
  @override
  bool get isSupported => false;

  @override
  Future<String?> start({
    required void Function(String) onText,
    required VoidCallback onDone,
  }) async => null;

  @override
  Future<void> stop() async {}
}

Future<ProviderContainer> _pump(WidgetTester tester, MockDio dio) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      dioProvider.overrideWithValue(dio),
      speechInputProvider.overrideWithValue(_NoSpeech()),
    ],
  );
  addTearDown(container.dispose);
  container.read(liveActivityProvider.notifier).start();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LiveActivityScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

TextField _field(WidgetTester tester, String label, {int index = 0}) =>
    tester.widget<TextField>(find.widgetWithText(TextField, label).at(index));

void main() {
  testWidgets('Add several adds each confirmed exercise, with no sets', (tester) async {
    final container = await _pump(tester, _dio());

    await tester.tap(find.text('Add several (speak or type a list)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1 row 2 bench press');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add 2 exercises'));
    await tester.pumpAndSettle();

    final added = container.read(liveActivityProvider)!.exercises;
    expect(added.map((e) => e.exerciseId), [2, 1]);
    expect(added.every((e) => e.sets.isEmpty), isTrue);
  });

  testWidgets('shows last time and a suggestion, and Use fills the sets from it', (tester) async {
    final container = await _pump(tester, _dio());
    container.read(liveActivityProvider.notifier).addExercise(1);
    await tester.pumpAndSettle();

    expect(find.textContaining('Last time · Sep 1: 3 × 8 @ 60 kg'), findsOneWidget);
    expect(find.text('Try 62.5 kg × 8.'), findsOneWidget);
    // No sets yet, so Use creates last time's three.
    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();

    final sets = container.read(liveActivityProvider)!.exercises.single.sets;
    expect(sets.map((s) => s.weightKg), [62.5, 62.5, 62.5]);
    expect(sets.map((s) => s.reps), [8, 8, 8]);
    // ...and the fields show it (they are not left on stale initial text).
    expect(_field(tester, 'kg').controller!.text, '62.5');
    expect(_field(tester, 'reps', index: 2).controller!.text, '8');
  });

  testWidgets("each new set's fields hint at the same set last time", (tester) async {
    final container = await _pump(tester, _dio());
    container.read(liveActivityProvider.notifier).addExercise(1);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add set'));
    await tester.pumpAndSettle();

    expect(_field(tester, 'kg').decoration!.hintText, '60');
    expect(_field(tester, 'reps').decoration!.hintText, '8');
    // The hint is not a value: nothing is logged until it is typed.
    expect(container.read(liveActivityProvider)!.exercises.single.sets.single.weightKg, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'kg'), '62.5');
    expect(container.read(liveActivityProvider)!.exercises.single.sets.single.weightKg, 62.5);
  });

  testWidgets('a set past the all-time best weight gets a trophy; warm-ups and ties do not', (
    tester,
  ) async {
    final container = await _pump(tester, _dio());
    final notifier = container.read(liveActivityProvider.notifier);
    notifier.addExercise(1);
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Add set'));
      await tester.pumpAndSettle();
    }
    expect(find.byIcon(Icons.emoji_events), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'kg').at(0), '80');
    await tester.enterText(find.widgetWithText(TextField, 'kg').at(1), '82.5');
    await tester.enterText(find.widgetWithText(TextField, 'kg').at(2), '82.5');
    await tester.pumpAndSettle();

    // Nothing is ticked off yet, so nothing can be a record.
    expect(find.byIcon(Icons.emoji_events), findsNothing);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('set-done')).at(i));
      await tester.pumpAndSettle();
    }

    // 80 only ties the record; 82.5 beats it once; the second 82.5 only ties that.
    expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    expect(find.byTooltip('New personal record'), findsOneWidget);
  });

  testWidgets('a set counts once it is ticked off, and its row turns green', (tester) async {
    final container = await _pump(tester, _dio());
    final notifier = container.read(liveActivityProvider.notifier);
    notifier.addExercise(1);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add set'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'kg'), '100');
    await tester.enterText(find.widgetWithText(TextField, 'reps'), '5');
    await tester.pumpAndSettle();

    Color? rowColor() {
      final row = find.ancestor(
        of: find.byKey(const ValueKey('set-done')),
        matching: find.byType(Container),
      );
      for (final element in row.evaluate()) {
        final decoration = (element.widget as Container).decoration;
        if (decoration is BoxDecoration && decoration.borderRadius != null) return decoration.color;
      }
      return null;
    }

    // Not ticked: not completed, not counted, no tint.
    var session = container.read(liveActivityProvider)!;
    expect(session.exercises.single.sets.single.completed, isFalse);
    expect(session.totalSets, 0);
    expect(session.totalVolumeKg, 0);
    expect(rowColor(), isNull);

    await tester.tap(find.byKey(const ValueKey('set-done')));
    await tester.pumpAndSettle();
    session = container.read(liveActivityProvider)!;
    expect(session.exercises.single.sets.single.completed, isTrue);
    expect(session.totalSets, 1);
    expect(session.totalVolumeKg, 500);
    final green = rowColor();
    expect(green, isNotNull);
    expect(green!.g, greaterThan(green.r)); // green-dominant

    await tester.tap(find.byKey(const ValueKey('set-done')));
    await tester.pumpAndSettle();
    expect(container.read(liveActivityProvider)!.totalSets, 0);
    expect(rowColor(), isNull);
  });

  testWidgets('logging works with no server: no hints, no trophies, nothing blocked', (
    tester,
  ) async {
    final container = await _pump(tester, _dio(historyOffline: true));
    container.read(liveActivityProvider.notifier).addExercise(1);
    await tester.pumpAndSettle();

    expect(find.textContaining('Last time'), findsNothing);
    await tester.tap(find.text('Add set'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'kg'), '100');
    await tester.enterText(find.widgetWithText(TextField, 'reps'), '5');
    await tester.pumpAndSettle();

    final set = container.read(liveActivityProvider)!.exercises.single.sets.single;
    expect(set.weightKg, 100);
    expect(set.reps, 5);
    expect(find.byIcon(Icons.emoji_events), findsNothing);
    expect(_field(tester, 'kg').decoration!.hintText, isNull);
  });

  testWidgets('removing a set removes that set, not the one whose text was last on screen', (
    tester,
  ) async {
    final container = await _pump(tester, _dio(historyOffline: true));
    container.read(liveActivityProvider.notifier).addExercise(2);
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Add set'));
      await tester.pumpAndSettle();
    }
    for (final (i, weight) in ['10', '20', '30'].indexed) {
      await tester.enterText(find.widgetWithText(TextField, 'kg').at(i), weight);
    }
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Set options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove set'));
    await tester.pumpAndSettle();

    expect(container.read(liveActivityProvider)!.exercises.single.sets.map((s) => s.weightKg), [
      20,
      30,
    ]);
    expect(_field(tester, 'kg', index: 0).controller!.text, '20');
    expect(_field(tester, 'kg', index: 1).controller!.text, '30');
  });

  testWidgets('two exercises can be made a superset, labelled, and split again', (tester) async {
    final container = await _pump(tester, _dio(historyOffline: true));
    final notifier = container.read(liveActivityProvider.notifier);
    notifier.addExercise(1);
    notifier.addExercise(2);
    await tester.pumpAndSettle();
    expect(find.textContaining('Superset'), findsNothing);

    await tester.tap(find.byTooltip('Exercise options').first);
    await tester.pumpAndSettle();
    expect(find.text('Remove from superset'), findsNothing);
    await tester.tap(find.text('Superset with next exercise'));
    await tester.pumpAndSettle();

    expect(find.text('Superset A'), findsNWidgets(2));
    expect(container.read(liveActivityProvider)!.exercises.map((e) => e.supersetGroup), [1, 1]);

    await tester.tap(find.byTooltip('Exercise options').last);
    await tester.pumpAndSettle();
    // The last exercise has nothing after it to link with.
    expect(find.text('Superset with next exercise'), findsNothing);
    await tester.tap(find.text('Remove from superset'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Superset'), findsNothing);
    expect(container.read(liveActivityProvider)!.exercises.map((e) => e.supersetGroup), [
      null,
      null,
    ]);
  });

  testWidgets('moving an exercise down reorders the cards and keeps their sets', (tester) async {
    final container = await _pump(tester, _dio(historyOffline: true));
    final notifier = container.read(liveActivityProvider.notifier);
    notifier.addExercise(1);
    notifier.addExercise(2);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add set').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'kg'), '77');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Exercise options').first);
    await tester.pumpAndSettle();
    expect(find.text('Move up'), findsNothing);
    await tester.tap(find.text('Move down'));
    await tester.pumpAndSettle();

    final exercises = container.read(liveActivityProvider)!.exercises;
    expect(exercises.map((e) => e.exerciseId), [2, 1]);
    // The 77 kg set moved with Bench Press, and is still what its field shows.
    expect(exercises.last.sets.single.weightKg, 77);
    expect(_field(tester, 'kg').controller!.text, '77');
    final order = [for (final t in tester.widgetList<Text>(find.byType(Text))) t.data];
    expect(order.indexOf('Row'), lessThan(order.indexOf('Bench Press')));
  });

  testWidgets('long-press-dragging a card down reorders the exercises', (tester) async {
    final container = await _pump(tester, _dio(historyOffline: true));
    final notifier = container.read(liveActivityProvider.notifier);
    notifier.addExercise(1);
    notifier.addExercise(2);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(find.text('Bench Press')));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 400));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(container.read(liveActivityProvider)!.exercises.map((e) => e.exerciseId), [2, 1]);
  });

  testWidgets('a routine superset is carried into the workout and labelled', (tester) async {
    final container = await _pump(tester, _dio(historyOffline: true));
    container
        .read(liveActivityProvider.notifier)
        .startFromRoutine(
          const Routine(
            id: 3,
            name: 'Upper',
            exercises: [
              RoutineExercise(exerciseId: 1, supersetGroup: 1),
              RoutineExercise(exerciseId: 2, supersetGroup: 1),
            ],
          ),
        );
    await tester.pumpAndSettle();

    expect(find.text('Superset A'), findsNWidgets(2));
  });
}
