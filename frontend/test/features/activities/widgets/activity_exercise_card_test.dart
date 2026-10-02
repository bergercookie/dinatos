import 'package:dinatos_frontend/core/dio_provider.dart';
import 'package:dinatos_frontend/features/activities/widgets/activity_exercise_card.dart';
import 'package:dinatos_frontend/models/activity.dart';
import 'package:dinatos_frontend/models/equipment.dart';
import 'package:dinatos_frontend/models/exercise.dart';
import 'package:dinatos_frontend/models/muscle_group.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/fakes.dart';

Response<List<dynamic>> _exercisesResponse(List<Map<String, dynamic>> items) => Response(
  requestOptions: RequestOptions(path: '/exercises'),
  statusCode: 200,
  data: items,
);

void main() {
  testWidgets("tapping an exercise's equipment chip lists other exercises using it", (
    tester,
  ) async {
    final dio = MockDio();
    when(() => dio.get<List<dynamic>>('/exercises', queryParameters: any(named: 'queryParameters')))
        .thenAnswer((invocation) async {
          final params = invocation.namedArguments[#queryParameters] as Map;
          if (params['equipment'] == 'barbell') {
            return _exercisesResponse([
              {
                'id': 5,
                'name': 'Bench Press',
                'tracks_weight': true,
                'tracks_reps': true,
                'tracks_distance': false,
                'tracks_duration': false,
                'is_custom': true,
                'equipment': 'barbell',
                'primary_muscles': ['chest'],
                'secondary_muscles': [],
              },
              {
                'id': 6,
                'name': 'Squat (Barbell)',
                'tracks_weight': true,
                'tracks_reps': true,
                'tracks_distance': false,
                'tracks_duration': false,
                'is_custom': true,
                'equipment': 'barbell',
                'primary_muscles': [],
                'secondary_muscles': [],
              },
            ]);
          }
          return _exercisesResponse([]);
        });
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ActivityExerciseCard(
              exercise: const ActivityExercise(exerciseId: 5),
              catalogExercise: const Exercise(
                id: 5,
                name: 'Bench Press',
                equipment: Equipment.barbell,
                primaryMuscles: [MuscleGroup.chest],
              ),
              onChanged: (_) {},
              onRemove: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Barbell'), findsOneWidget);
    expect(find.text('Chest'), findsOneWidget);

    await tester.tap(find.text('Barbell'));
    await tester.pumpAndSettle();

    expect(find.text('Uses Barbell'), findsOneWidget);
    expect(find.text('Squat (Barbell)'), findsOneWidget);
  });

  testWidgets("tapping an exercise's muscle chip lists other exercises training it", (
    tester,
  ) async {
    final dio = MockDio();
    when(() => dio.get<List<dynamic>>('/exercises', queryParameters: any(named: 'queryParameters')))
        .thenAnswer((invocation) async {
          final params = invocation.namedArguments[#queryParameters] as Map;
          if (params['muscle'] == 'chest') {
            return _exercisesResponse([
              {
                'id': 7,
                'name': 'Cable Fly',
                'tracks_weight': true,
                'tracks_reps': true,
                'tracks_distance': false,
                'tracks_duration': false,
                'is_custom': true,
                'equipment': 'cable',
                'primary_muscles': ['chest'],
                'secondary_muscles': [],
              },
            ]);
          }
          return _exercisesResponse([]);
        });
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ActivityExerciseCard(
              exercise: const ActivityExercise(exerciseId: 5),
              catalogExercise: const Exercise(
                id: 5,
                name: 'Bench Press',
                primaryMuscles: [MuscleGroup.chest],
              ),
              onChanged: (_) {},
              onRemove: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chest'));
    await tester.pumpAndSettle();

    expect(find.text('Trains Chest'), findsOneWidget);
    expect(find.text('Cable Fly'), findsOneWidget);
  });

  testWidgets('shows no chips at all when the exercise has no equipment or muscles', (
    tester,
  ) async {
    final dio = MockDio();
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ActivityExerciseCard(
              exercise: const ActivityExercise(exerciseId: 1),
              catalogExercise: const Exercise(id: 1, name: 'Plank'),
              onChanged: (_) {},
              onRemove: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ActionChip), findsNothing);
  });
}
