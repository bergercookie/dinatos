import 'package:dinatos_frontend/core/dio_provider.dart';
import 'package:dinatos_frontend/features/exercises/exercise_tutorial_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fakes.dart';

Response<Map<String, dynamic>> _exerciseResponse(int id, String name) => Response(
  requestOptions: RequestOptions(path: '/exercises/$id'),
  statusCode: 200,
  data: {
    'id': id,
    'name': name,
    'tracks_weight': true,
    'tracks_reps': true,
    'tracks_distance': false,
    'tracks_duration': false,
  },
);

void main() {
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
}
