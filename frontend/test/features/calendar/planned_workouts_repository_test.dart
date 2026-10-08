import 'package:dinatos_frontend/core/api_exception.dart';
import 'package:dinatos_frontend/features/calendar/planned_workouts_repository.dart';
import 'package:dinatos_frontend/models/planned_workout.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fakes.dart';

Response<T> _ok<T>(String path, T data, {int status = 200}) => Response(
  requestOptions: RequestOptions(path: path),
  statusCode: status,
  data: data,
);

Map<String, dynamic> _json({int id = 1}) => {
  'id': id,
  'title': 'Push',
  'notes': null,
  'scheduled_at': '2030-05-10T18:00:00Z',
  'routine_id': 4,
  'duration_minutes': 60,
  'reminder_minutes': 30,
  'completed_activity_id': null,
};

DioException _failure(String path, int status, String detail) => DioException(
  requestOptions: RequestOptions(path: path),
  response: Response(
    requestOptions: RequestOptions(path: path),
    statusCode: status,
    data: {'detail': detail},
  ),
  type: DioExceptionType.badResponse,
);

void main() {
  test('list sends the bounds as UTC and parses the plans', () async {
    final dio = buildMockDio();
    when(
      () => dio.get<List<dynamic>>(
        '/planned-workouts',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) async => _ok('/planned-workouts', [_json(id: 1), _json(id: 2)]));

    final plans = await PlannedWorkoutsRepository(dio)
        .list(since: DateTime.utc(2030, 1, 1), until: DateTime.utc(2030, 2, 1));

    expect(plans.map((p) => p.id), [1, 2]);
    verify(
      () => dio.get<List<dynamic>>(
        '/planned-workouts',
        queryParameters: {'since': '2030-01-01T00:00:00.000Z', 'until': '2030-02-01T00:00:00.000Z'},
      ),
    ).called(1);
  });

  test('create posts the plan and returns the saved one', () async {
    final dio = buildMockDio();
    final plan = PlannedWorkout(
      title: 'Push',
      scheduledAt: DateTime.utc(2030, 5, 10, 18),
      routineId: 4,
    );
    when(() => dio.post<Map<String, dynamic>>('/planned-workouts', data: plan.toJson()))
        .thenAnswer((_) async => _ok('/planned-workouts', _json(), status: 201));

    final saved = await PlannedWorkoutsRepository(dio).create(plan);

    expect(saved.id, 1);
  });

  test('replace puts, get fetches, delete deletes', () async {
    final dio = buildMockDio();
    final plan = PlannedWorkout(title: 'Push', scheduledAt: DateTime.utc(2030, 5, 10, 18));
    when(() => dio.put<Map<String, dynamic>>('/planned-workouts/1', data: plan.toJson()))
        .thenAnswer((_) async => _ok('/planned-workouts/1', _json()));
    when(() => dio.get<Map<String, dynamic>>('/planned-workouts/1'))
        .thenAnswer((_) async => _ok('/planned-workouts/1', _json()));
    when(() => dio.delete<void>('/planned-workouts/1'))
        .thenAnswer((_) async => _ok<void>('/planned-workouts/1', null, status: 204));
    final repository = PlannedWorkoutsRepository(dio);

    expect((await repository.replace(1, plan)).title, 'Push');
    expect((await repository.get(1)).id, 1);
    await repository.delete(1);
    verify(() => dio.delete<void>('/planned-workouts/1')).called(1);
  });

  test('an API error becomes an ApiException', () async {
    final dio = buildMockDio();
    when(() => dio.get<Map<String, dynamic>>('/planned-workouts/9'))
        .thenThrow(_failure('/planned-workouts/9', 404, 'planned workout not found'));

    await expectLater(
      PlannedWorkoutsRepository(dio).get(9),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'planned workout not found')),
    );
  });

  test('the calendar feed can be read, enabled and disabled', () async {
    final dio = buildMockDio();
    when(() => dio.get<Map<String, dynamic>>('/profile/calendar'))
        .thenAnswer((_) async => _ok('/profile/calendar', {'token': null, 'path': null}));
    when(() => dio.post<Map<String, dynamic>>('/profile/calendar')).thenAnswer(
      (_) async => _ok('/profile/calendar', {'token': 'abc', 'path': '/calendar/abc.ics'}),
    );
    when(() => dio.delete<void>('/profile/calendar'))
        .thenAnswer((_) async => _ok<void>('/profile/calendar', null, status: 204));
    final repository = PlannedWorkoutsRepository(dio);

    expect((await repository.feed()).enabled, isFalse);
    final enabled = await repository.enableFeed();
    expect(enabled.enabled, isTrue);
    expect(enabled.path, '/calendar/abc.ics');
    await repository.disableFeed();
    verify(() => dio.delete<void>('/profile/calendar')).called(1);
  });
}
