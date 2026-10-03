import 'package:dinatos_frontend/core/dio_provider.dart';
import 'package:dinatos_frontend/core/widgets/line_chart.dart';
import 'package:dinatos_frontend/features/progress/exercise_progress_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fakes.dart';

Response<T> _ok<T>(String path, T data) => Response(
  requestOptions: RequestOptions(path: path),
  statusCode: 200,
  data: data,
);

Map<String, dynamic> _session(int day, double? kg, int reps, {int count = 3}) => {
  'activity_id': day,
  'activity_title': 'Session $day',
  'started_at': '2026-03-${day.toString().padLeft(2, '0')}T10:00:00Z',
  'sets': [
    for (var i = 0; i < count; i++)
      {
        'set_type': 'normal',
        'weight_kg': kg,
        'reps': reps,
        'distance_km': null,
        'duration_seconds': null,
        'rpe': null,
      },
  ],
};

/// [history] newest first, as the server sends it.
Future<void> _pump(WidgetTester tester, List<Map<String, dynamic>> history) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dio = buildMockDio();
  when(() => dio.get<Map<String, dynamic>>('/exercises/1')).thenAnswer(
    (_) async => _ok<Map<String, dynamic>>('/exercises/1', {
      'id': 1,
      'name': 'Bench Press',
      'tracks_weight': true,
      'tracks_reps': true,
      'tracks_distance': false,
      'tracks_duration': false,
      'is_custom': true,
      'equipment': 'barbell',
      'primary_muscles': <String>[],
      'secondary_muscles': <String>[],
    }),
  );
  when(
    () => dio.get<List<dynamic>>(
      '/exercises/1/history',
      queryParameters: any(named: 'queryParameters'),
    ),
  ).thenAnswer((_) async => _ok<List<dynamic>>('/exercises/1/history', history));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: const MaterialApp(home: ExerciseProgressScreen(exerciseId: 1)),
    ),
  );
  await tester.pumpAndSettle();
}

List<double> _plotted(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).values;

void main() {
  testWidgets('charts the estimated 1RM per session, oldest first, and suggests the next step', (
    tester,
  ) async {
    await _pump(tester, [_session(15, 70, 5), _session(8, 65, 5), _session(1, 60, 5)]);

    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Estimated one-rep max'), findsOneWidget);
    expect(_plotted(tester), [
      for (final kg in [60, 65, 70]) closeTo(kg * (1 + 5 / 30), 1e-9),
    ]);
    expect(find.text('Next time'), findsOneWidget);
    expect(find.text('Last time 3 × 5 @ 70 kg. Try 72.5 kg × 5.'), findsOneWidget);
    expect(find.text('Progress has stalled'), findsNothing);
    expect(find.text('Recent sessions'), findsOneWidget);
    expect(find.text('3 × 5 @ 70 kg'), findsOneWidget);
  });

  testWidgets('the metric can be switched to top set or volume', (tester) async {
    await _pump(tester, [_session(8, 65, 5), _session(1, 60, 5)]);

    await tester.tap(find.text('Top set'));
    await tester.pumpAndSettle();
    expect(find.text('Heaviest set'), findsOneWidget);
    expect(_plotted(tester), [60, 65]);

    await tester.tap(find.text('Volume'));
    await tester.pumpAndSettle();
    expect(find.text('Total volume'), findsOneWidget);
    expect(_plotted(tester), [900, 975]);
  });

  testWidgets('reports a stall once the best is several sessions old', (tester) async {
    await _pump(tester, [
      _session(20, 62.5, 5),
      _session(15, 62.5, 5),
      _session(10, 60, 5),
      _session(8, 62.5, 5),
      _session(5, 65, 5),
      _session(1, 60, 5),
    ]);

    expect(find.text('Progress has stalled'), findsOneWidget);
    expect(find.textContaining('No new best in the last 4 sessions'), findsOneWidget);
  });

  testWidgets('a body-weight exercise is charted by reps', (tester) async {
    await _pump(tester, [_session(8, null, 12), _session(1, null, 10)]);

    expect(find.text('Most reps in a set'), findsOneWidget);
    expect(_plotted(tester), [10, 12]);
    // Nothing to switch between: only one metric applies.
    expect(find.byType(SegmentedButton<ProgressMetric>), findsNothing);
    expect(find.text('Last time 2 × 12. Try 13 reps.'), findsNothing);
    expect(find.text('Last time 3 × 12. Try 13 reps.'), findsOneWidget);
  });

  testWidgets('with no history it says so, instead of showing an empty chart', (tester) async {
    await _pump(tester, []);

    expect(find.text('No sessions yet'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
  });

  testWidgets('a single session is still drawn', (tester) async {
    await _pump(tester, [_session(1, 60, 5)]);

    expect(_plotted(tester), hasLength(1));
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
