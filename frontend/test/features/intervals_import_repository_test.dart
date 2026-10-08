import 'package:dinatos_frontend/core/api_exception.dart';
import 'package:dinatos_frontend/features/imports/intervals_import_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fakes.dart';

DioException _error(int status, Object data, String path) => DioException(
  requestOptions: RequestOptions(path: path),
  response: Response(
    requestOptions: RequestOptions(path: path),
    statusCode: status,
    data: data,
  ),
);

void main() {
  final oldest = DateTime(2026, 3, 1);
  final newest = DateTime(2026, 3, 31);

  test('preview posts the source (key in the body) and parses the activities', () async {
    final dio = MockDio();
    when(
      () => dio.post<Map<String, dynamic>>(
        '/imports/intervals/preview',
        data: {
          'athlete_id': '0',
          'api_key': 'secret',
          'oldest': '2026-03-01',
          'newest': '2026-03-31',
        },
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/imports/intervals/preview'),
        statusCode: 200,
        data: {
          'activities': [
            {
              'id': 'i100',
              'name': 'Morning run',
              'type': 'Run',
              'started_at': '2026-03-01T07:30:00',
              'duration_seconds': 1800,
              'distance_km': 5.0,
              'importable': true,
              'already_imported': false,
              'possible_duplicate_of': null,
            },
            {
              'id': 'i102',
              'name': 'Stub',
              'started_at': null,
              'importable': false,
              'unimportable_reason': 'STRAVA',
            },
          ],
        },
      ),
    );

    final activities = await IntervalsImportRepository(dio)
        .preview(athleteId: '0', apiKey: 'secret', oldest: oldest, newest: newest);

    expect(activities, hasLength(2));
    expect(activities[0].distanceKm, 5.0);
    expect(activities[0].startedAt, DateTime(2026, 3, 1, 7, 30));
    expect(activities[0].selectedByDefault, isTrue);
    expect(activities[1].importable, isFalse);
    expect(activities[1].selectedByDefault, isFalse);
  });

  test('import sends the chosen ids and force as a query parameter', () async {
    final dio = MockDio();
    when(
      () => dio.post<Map<String, dynamic>>(
        '/imports/intervals/activities',
        queryParameters: {'force': true},
        data: {
          'athlete_id': 'i42',
          'api_key': 'secret',
          'oldest': '2026-03-01',
          'newest': '2026-03-31',
          'activity_ids': ['i100'],
        },
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/imports/intervals/activities'),
        statusCode: 200,
        data: {
          'activities_created': 1,
          'exercises_created': 1,
          'created_exercises': [
            {'id': 4, 'name': 'Running'},
          ],
        },
      ),
    );

    final result = await IntervalsImportRepository(dio).import(
      athleteId: 'i42',
      apiKey: 'secret',
      oldest: oldest,
      newest: newest,
      activityIds: ['i100'],
      force: true,
    );

    expect(result.activitiesCreated, 1);
    expect(result.createdExercises.single.name, 'Running');
  });

  Future<Object?> importError(DioException error) async {
    final dio = MockDio();
    when(
      () => dio.post<Map<String, dynamic>>(
        any(),
        queryParameters: any(named: 'queryParameters'),
        data: any(named: 'data'),
      ),
    ).thenThrow(error);
    try {
      await IntervalsImportRepository(
        dio,
      ).import(athleteId: '0', apiKey: 'k', oldest: oldest, newest: newest, activityIds: ['i100']);
    } on Object catch (caught) {
      return caught;
    }
    return null;
  }

  test('a 409 becomes IntervalsAlreadyImportedException naming the ids', () async {
    final caught = await importError(
      _error(409, {
        'detail': {
          'message': 'already imported',
          'already_imported': {'i100': '2026-01-01T00:00:00'},
        },
      }, '/imports/intervals/activities'),
    );

    expect(caught, isA<IntervalsAlreadyImportedException>());
    expect((caught! as IntervalsAlreadyImportedException).activityIds, ['i100']);
  });

  test('a 409 without a readable detail still means already imported', () async {
    final caught = await importError(
      _error(409, {
        'detail': {'message': 'x'},
      }, '/imports/intervals/activities'),
    );

    expect((caught! as IntervalsAlreadyImportedException).activityIds, isEmpty);
  });

  test('a 422 with an object detail surfaces its message', () async {
    final caught = await importError(
      _error(422, {
        'detail': {
          'message': 'some selected activities were not found',
          'not_found': ['x'],
        },
      }, '/imports/intervals/activities'),
    );

    expect(caught, isA<ApiException>());
    expect((caught! as ApiException).message, contains('not found'));
  });

  test('a rejected key (400 with a string detail) is an ApiException', () async {
    final caught = await importError(
      _error(400, {
        'detail': 'Intervals.icu rejected the API key or athlete id',
      }, '/imports/intervals/activities'),
    );

    expect((caught! as ApiException).message, contains('API key'));
  });

  test('preview failures are translated too', () async {
    final dio = MockDio();
    when(() => dio.post<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenThrow(
      _error(502, {'detail': 'could not reach Intervals.icu'}, '/imports/intervals/preview'),
    );

    await expectLater(
      IntervalsImportRepository(dio)
          .preview(athleteId: '0', apiKey: 'k', oldest: oldest, newest: newest),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 502)),
    );
  });
}
