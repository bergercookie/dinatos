import 'package:dinatos_frontend/core/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefers the backend\'s {"detail": "..."} body over a generic message', () {
    final requestOptions = RequestOptions(path: '/exercises');
    final dioError = DioException(
      requestOptions: requestOptions,
      response: Response(
        requestOptions: requestOptions,
        statusCode: 404,
        data: {'detail': 'exercise not found'},
      ),
      type: DioExceptionType.badResponse,
    );

    final exception = ApiException.fromDioException(dioError);

    expect(exception.message, 'exercise not found');
    expect(exception.statusCode, 404);
    expect(exception.isNotFound, isTrue);
  });

  test('falls back to a fixed message on a connection error', () {
    final requestOptions = RequestOptions(path: '/exercises');
    final dioError = DioException(
      requestOptions: requestOptions,
      type: DioExceptionType.connectionError,
    );

    expect(ApiException.fromDioException(dioError).message, 'Could not reach the server.');
  });

  test('joins a list detail (request validation, backup problems) one per line', () {
    final requestOptions = RequestOptions(path: '/profile/import');
    DioException error(Object detail) => DioException(
      requestOptions: requestOptions,
      response: Response(requestOptions: requestOptions, statusCode: 422, data: {'detail': detail}),
      type: DioExceptionType.badResponse,
    );

    expect(
      ApiException.fromDioException(
        error([
          {
            'loc': ['body', 'format'],
            'msg': 'Input should be dinatos-user-export',
          },
          {
            'loc': ['body'],
            'other': 1,
          },
        ]),
      ).message,
      startsWith('Input should be dinatos-user-export\n'),
    );
    final backup = ApiException.fromDioException(error(['unknown table', 'users[0]: bad']));
    expect(backup.message, 'unknown table\nusers[0]: bad');
    expect(backup.statusCode, 422);
  });
}
