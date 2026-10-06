import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/dio_provider.dart';
import '../../models/api_key.dart';

final apiKeysRepositoryProvider = Provider<ApiKeysRepository>((ref) {
  return ApiKeysRepository(ref.watch(dioProvider));
});

class ApiKeysRepository {
  ApiKeysRepository(this._dio);

  final Dio _dio;

  Future<List<ApiKeySummary>> list() async {
    try {
      final response = await _dio.get<List<dynamic>>('/api-keys');
      return response.data!.map((e) => ApiKeySummary.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  /// The returned [CreatedApiKey.key] is shown to the person once and never
  /// again -- the server keeps only a hash.
  Future<CreatedApiKey> create(String name) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>('/api-keys', data: {'name': name});
      return CreatedApiKey.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _dio.delete<void>('/api-keys/$id');
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }
}
