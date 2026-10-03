import 'dart:convert';
import 'dart:typed_data';

import 'package:dinatos_frontend/core/api_exception.dart';
import 'package:dinatos_frontend/core/file_io.dart';
import 'package:dinatos_frontend/features/profile/profile_repository.dart';
import 'package:dinatos_frontend/models/data_transfer_result.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fakes.dart';

FileContent _file(String content) =>
    FileContent('export.json', Uint8List.fromList(utf8.encode(content)));

Map<String, dynamic> _resultJson() => {
  'mode': 'merge',
  'created': {'exercises': 0, 'routines': 2, 'activities': 1, 'measurements': 0},
  'skipped': {'exercises': 0, 'routines': 1, 'activities': 0, 'measurements': 0},
  'deleted': {'exercises': 0, 'routines': 0, 'activities': 0, 'measurements': 0},
};

void main() {
  setUpAll(() {
    registerFallbackValue(Options());
  });

  group('exportMyData', () {
    test('returns the downloaded bytes under the server-suggested filename', () async {
      final dio = buildMockDio();
      when(() => dio.get<List<int>>('/profile/export', options: any(named: 'options'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/profile/export'),
          statusCode: 200,
          data: utf8.encode('{}'),
          headers: Headers.fromMap({
            'content-disposition': ['attachment; filename="dinatos-export-1.json"'],
          }),
        ),
      );

      final file = await ProfileRepository(dio).exportMyData();

      expect(file.name, 'dinatos-export-1.json');
      expect(utf8.decode(file.bytes), '{}');
    });

    test('falls back to a default name', () async {
      final dio = buildMockDio();
      when(() => dio.get<List<int>>('/profile/export', options: any(named: 'options'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/profile/export'),
          statusCode: 200,
          data: [123, 125],
        ),
      );

      expect((await ProfileRepository(dio).exportMyData()).name, 'dinatos-export.json');
    });

    test('surfaces a server error', () async {
      final dio = buildMockDio();
      when(() => dio.get<List<int>>('/profile/export', options: any(named: 'options'))).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/profile/export'),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(ProfileRepository(dio).exportMyData(), throwsA(isA<ApiException>()));
    });
  });

  group('importMyData', () {
    test('posts the parsed document with the chosen mode and parses the result', () async {
      final dio = buildMockDio();
      when(
        () => dio.post<Map<String, dynamic>>(
          '/profile/import',
          queryParameters: any(named: 'queryParameters'),
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/profile/import'),
          statusCode: 200,
          data: _resultJson(),
        ),
      );

      final result = await ProfileRepository(dio)
          .importMyData(_file('{"format":"dinatos-user-export"}'), UserImportMode.replace);

      verify(
        () => dio.post<Map<String, dynamic>>(
          '/profile/import',
          queryParameters: {'mode': 'replace'},
          data: {'format': 'dinatos-user-export'},
        ),
      ).called(1);
      expect(result.created.routines, 2);
      expect(
        result.summary(),
        'Imported 2 routines, 1 activity; skipped 1 routine already present.',
      );
    });

    test('rejects a file that is not JSON without calling the server', () async {
      final dio = buildMockDio();

      await expectLater(
        ProfileRepository(dio).importMyData(_file('not json'), UserImportMode.merge),
        throwsA(
          isA<ApiException>().having((e) => e.message, 'message', contains('not valid JSON')),
        ),
      );
      verifyNever(
        () => dio.post<Map<String, dynamic>>(
          any(),
          queryParameters: any(named: 'queryParameters'),
          data: any(named: 'data'),
        ),
      );
    });

    test('rejects JSON that is not an object', () async {
      await expectLater(
        ProfileRepository(buildMockDio()).importMyData(_file('[1,2]'), UserImportMode.merge),
        throwsA(
          isA<ApiException>().having((e) => e.message, 'message', contains('not a Dinatos export')),
        ),
      );
    });

    test('surfaces the server validation error', () async {
      final dio = buildMockDio();
      when(
        () => dio.post<Map<String, dynamic>>(
          '/profile/import',
          queryParameters: any(named: 'queryParameters'),
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/profile/import'),
          response: Response(
            requestOptions: RequestOptions(path: '/profile/import'),
            statusCode: 422,
            data: {'detail': 'exercise "X" is used but not defined'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      await expectLater(
        ProfileRepository(dio).importMyData(_file('{}'), UserImportMode.merge),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 422)),
      );
    });
  });

  group('ImportCounts / UserImportResult', () {
    test('describe lists only what is non-zero, with singular and plural', () {
      expect(const ImportCounts().describe(), 'nothing');
      expect(
        const ImportCounts(exercises: 1, routines: 2, activities: 1, measurements: 3).describe(),
        '1 exercise, 2 routines, 1 activity, 3 measurements',
      );
    });

    test('summary mentions replaced data', () {
      final result = UserImportResult.fromJson({
        ..._resultJson(),
        'mode': 'replace',
        'skipped': <String, dynamic>{},
        'deleted': <String, dynamic>{'routines': 3, 'activities': 2},
      });
      expect(result.mode, UserImportMode.replace);
      expect(
        result.summary(),
        'Imported 2 routines, 1 activity; replaced 3 routines, 2 activities.',
      );
    });
  });
}
