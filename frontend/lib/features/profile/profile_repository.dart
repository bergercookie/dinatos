import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/dio_provider.dart';
import '../../models/profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(dioProvider));
});

/// One row per user -- no id in the path, always the caller's own (see
/// docs/architecture/backend.md's "API surface").
class ProfileRepository {
  ProfileRepository(this._dio);

  final Dio _dio;

  Future<Profile> get() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/profile');
      return Profile.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<Profile> update(Profile profile) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>('/profile', data: profile.toJson());
      return Profile.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }
}
