import 'package:dinatos_frontend/core/api_exception.dart';
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

    final user = await AdminRepository(
      dio,
    ).createUser(email: 'new@example.com', password: 'hunter22', isAdmin: true);

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
}
