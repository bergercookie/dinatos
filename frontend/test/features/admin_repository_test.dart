import 'dart:convert';
import 'dart:typed_data';

import 'package:dinatos_frontend/core/api_exception.dart';
import 'package:dinatos_frontend/core/file_io.dart';
import 'package:dinatos_frontend/features/admin/admin_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fakes.dart';

void main() {
  test('listUsers parses the account list', () async {
    final dio = buildMockDio();
    when(() => dio.get<List<dynamic>>('/admin/users')).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/admin/users'),
        statusCode: 200,
        data: [
          {'id': 1, 'email': 'admin@example.com', 'is_admin': true},
          {'id': 2, 'email': 'member@example.com', 'is_admin': false},
        ],
      ),
    );

    final users = await AdminRepository(dio).listUsers();

    expect(users.map((u) => u.email), ['admin@example.com', 'member@example.com']);
    expect(users.map((u) => u.isAdmin), [true, false]);
  });

  test('createUser posts the new account and returns it', () async {
    final dio = buildMockDio();
    when(() => dio.post<Map<String, dynamic>>('/admin/users', data: any(named: 'data'))).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/admin/users'),
        statusCode: 201,
        data: {'id': 3, 'email': 'new@example.com', 'is_admin': true},
      ),
    );

    final user = await AdminRepository(dio)
        .createUser(email: 'new@example.com', password: 'hunter22', isAdmin: true);

    expect(user.email, 'new@example.com');
    expect(user.isAdmin, isTrue);
    verify(
      () => dio.post<Map<String, dynamic>>(
        '/admin/users',
        data: {'email': 'new@example.com', 'password': 'hunter22', 'is_admin': true},
      ),
    ).called(1);
  });

  test('createUser surfaces the server error message', () async {
    final dio = buildMockDio();
    when(() => dio.post<Map<String, dynamic>>('/admin/users', data: any(named: 'data'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/admin/users'),
        response: Response(
          requestOptions: RequestOptions(path: '/admin/users'),
          statusCode: 409,
          data: {'detail': 'email already registered'},
        ),
      ),
    );

    expect(
      AdminRepository(dio).createUser(email: 'a@example.com', password: 'hunter22', isAdmin: false),
      throwsA(isA<ApiException>().having((e) => e.isConflict, 'isConflict', isTrue)),
    );
  });

  group('backup', () {
    test('downloadBackup returns the bytes under the server-suggested filename', () async {
      final dio = buildMockDio();
      when(() => dio.get<List<int>>('/admin/backup', options: any(named: 'options'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/admin/backup'),
          statusCode: 200,
          data: utf8.encode('{"format":"dinatos-backup"}'),
          headers: Headers.fromMap({
            'content-disposition': ['attachment; filename="dinatos-backup-1.json"'],
          }),
        ),
      );

      final file = await AdminRepository(dio).downloadBackup();

      expect(file.name, 'dinatos-backup-1.json');
      expect(utf8.decode(file.bytes), '{"format":"dinatos-backup"}');
      final options =
          verify(() => dio.get<List<int>>('/admin/backup', options: captureAny(named: 'options')))
                  .captured
                  .single
              as Options;
      expect(options.responseType, ResponseType.bytes);
    });

    test('downloadBackup uses a default name when the header is not visible', () async {
      final dio = buildMockDio();
      when(() => dio.get<List<int>>('/admin/backup', options: any(named: 'options'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/admin/backup'),
          statusCode: 200,
          data: [123, 125],
        ),
      );

      expect((await AdminRepository(dio).downloadBackup()).name, 'dinatos-backup.json');
    });

    test('downloadBackup surfaces the server error (e.g. not an admin)', () async {
      final dio = buildMockDio();
      when(() => dio.get<List<int>>('/admin/backup', options: any(named: 'options'))).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/admin/backup'),
          response: Response(
            requestOptions: RequestOptions(path: '/admin/backup'),
            statusCode: 403,
            data: {'detail': 'admin access required'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      await expectLater(
        AdminRepository(dio).downloadBackup(),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'admin access required')),
      );
    });

    test('restoreBackup uploads the file with confirm=true and parses the result', () async {
      final dio = buildMockDio();
      when(() => dio.post<Map<String, dynamic>>('/admin/backup/restore', data: any(named: 'data')))
          .thenAnswer(
            (_) async => Response(
              requestOptions: RequestOptions(path: '/admin/backup/restore'),
              statusCode: 200,
              data: {
                'rows': {'users': 3, 'routines': 4},
                'session_kept': false,
              },
            ),
          );

      final result = await AdminRepository(dio)
          .restoreBackup(FileContent('b.json', Uint8List.fromList([123, 125])));

      expect(result.rows, {'users': 3, 'routines': 4});
      expect(result.sessionKept, isFalse);
      final form =
          verify(
                () => dio.post<Map<String, dynamic>>(
                  '/admin/backup/restore',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as FormData;
      expect(form.fields.map((e) => '${e.key}=${e.value}'), ['confirm=true']);
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'b.json');
    });

    test('restoreBackup surfaces a rejected document', () async {
      final dio = buildMockDio();
      when(() => dio.post<Map<String, dynamic>>('/admin/backup/restore', data: any(named: 'data')))
          .thenThrow(
            DioException(
              requestOptions: RequestOptions(path: '/admin/backup/restore'),
              response: Response(
                requestOptions: RequestOptions(path: '/admin/backup/restore'),
                statusCode: 422,
                data: {
                  'detail': ['unknown table "x"'],
                },
              ),
              type: DioExceptionType.badResponse,
            ),
          );

      await expectLater(
        AdminRepository(dio).restoreBackup(FileContent('b.json', Uint8List(0))),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'unknown table "x"')),
      );
    });
  });
}
