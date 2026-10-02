import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/dio_provider.dart';
import '../../models/user.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(ref.watch(dioProvider));
});

/// Account administration -- every endpoint here is admin-only server-side
/// (`/admin/*`), whatever `DINATOS_ALLOW_REGISTRATION` is set to.
class AdminRepository {
  AdminRepository(this._dio);

  final Dio _dio;

  Future<List<User>> listUsers() async {
    try {
      final response = await _dio.get<List<dynamic>>('/admin/users');
      return response.data!.map((json) => User.fromJson(json as Map<String, dynamic>)).toList();
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<User> createUser({
    required String email,
    required String password,
    required bool isAdmin,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/admin/users',
        data: {'email': email, 'password': password, 'is_admin': isAdmin},
      );
      return User.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }
}
