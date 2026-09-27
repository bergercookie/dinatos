import 'package:dinatos_frontend/features/imports/hevy_import_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fakes.dart';

class _AnyFormData extends Matcher {
  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) => item is FormData;

  @override
  Description describe(Description description) => description.add('is a FormData');
}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
  });

  test('importWorkouts posts multipart form data and parses the result', () async {
    final dio = MockDio();
    when(
      () => dio.post<Map<String, dynamic>>(
        '/imports/hevy/workouts',
        queryParameters: {'force': false},
        data: any(named: 'data', that: _AnyFormData()),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/imports/hevy/workouts'),
        statusCode: 200,
        data: {'activities_created': 75, 'exercises_created': 3},
      ),
    );
    final repository = HevyImportRepository(dio);

    final result = await repository.importWorkouts([1, 2, 3], 'workout_data.csv');

    expect(result.activitiesCreated, 75);
    expect(result.exercisesCreated, 3);
  });

  test('importMeasurements posts multipart form data and parses the result', () async {
    final dio = MockDio();
    when(
      () => dio.post<Map<String, dynamic>>(
        '/imports/hevy/measurements',
        queryParameters: {'force': false},
        data: any(named: 'data', that: _AnyFormData()),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/imports/hevy/measurements'),
        statusCode: 200,
        data: {'measurements_created': 12},
      ),
    );
    final repository = HevyImportRepository(dio);

    final result = await repository.importMeasurements([1, 2, 3], 'measurement_data.csv');

    expect(result.measurementsCreated, 12);
  });

  test('a 409 becomes HevyImportAlreadyDoneException with the backend\'s detail', () async {
    final dio = MockDio();
    when(
      () => dio.post<Map<String, dynamic>>(
        '/imports/hevy/workouts',
        queryParameters: {'force': false},
        data: any(named: 'data'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/imports/hevy/workouts'),
        response: Response(
          requestOptions: RequestOptions(path: '/imports/hevy/workouts'),
          statusCode: 409,
          data: {
            'detail': {
              'message': 'already imported',
              'previously_imported_at': '2026-01-01T00:00:00Z',
              'previous_filename': 'workout_data.csv',
            },
          },
        ),
      ),
    );
    final repository = HevyImportRepository(dio);

    await expectLater(
      repository.importWorkouts([1, 2, 3], 'workout_data.csv'),
      throwsA(
        isA<HevyImportAlreadyDoneException>()
            .having((e) => e.previousFilename, 'previousFilename', 'workout_data.csv')
            .having((e) => e.previouslyImportedAt, 'previouslyImportedAt', '2026-01-01T00:00:00Z'),
      ),
    );
  });

  test('a force=true retry is sent as a query parameter', () async {
    final dio = MockDio();
    when(
      () => dio.post<Map<String, dynamic>>(
        '/imports/hevy/workouts',
        queryParameters: {'force': true},
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/imports/hevy/workouts'),
        statusCode: 200,
        data: {'activities_created': 1, 'exercises_created': 0},
      ),
    );
    final repository = HevyImportRepository(dio);

    final result = await repository.importWorkouts([1, 2, 3], 'workout_data.csv', force: true);

    expect(result.activitiesCreated, 1);
  });

  test('any other error maps to ApiException', () async {
    final dio = MockDio();
    when(
      () => dio.post<Map<String, dynamic>>(
        '/imports/hevy/workouts',
        queryParameters: {'force': false},
        data: any(named: 'data'),
      ),
    ).thenThrow(DioException(requestOptions: RequestOptions(path: '/imports/hevy/workouts')));
    final repository = HevyImportRepository(dio);

    await expectLater(
      repository.importWorkouts([1, 2, 3], 'workout_data.csv'),
      throwsA(isA<Exception>().having((e) => e is HevyImportAlreadyDoneException, 'is 409', false)),
    );
  });
}
