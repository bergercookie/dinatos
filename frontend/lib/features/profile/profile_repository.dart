import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/dio_provider.dart';
import '../../core/file_io.dart';
import '../../models/data_transfer_result.dart';
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

  /// Saves (or, with null/blank, removes) this user's own WorkoutX API key.
  /// Separate from [update] since the key is write-only on the backend.
  Future<Profile> setWorkoutxApiKey(String? key) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/profile',
        data: {'workoutx_api_key': key},
      );
      return Profile.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  /// The caller's own settings, routines, activities and measurements as a
  /// JSON file (`GET /profile/export`). No password, no API key.
  Future<FileContent> exportMyData() async {
    try {
      final response = await _dio.get<List<int>>(
        '/profile/export',
        options: Options(responseType: ResponseType.bytes),
      );
      return FileContent(
        filenameFromContentDisposition(
          response.headers.value('content-disposition'),
          'dinatos-export.json',
        ),
        Uint8List.fromList(response.data!),
      );
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  /// Loads a file from [exportMyData] into the caller's own account. A file
  /// that is not JSON, or not an object, never reaches the server.
  Future<UserImportResult> importMyData(FileContent file, UserImportMode mode) async {
    final Object? document;
    try {
      document = jsonDecode(utf8.decode(file.bytes));
    } on FormatException {
      throw const ApiException('That file is not valid JSON.');
    }
    if (document is! Map<String, dynamic>) {
      throw const ApiException('That file is not a Dinatos export.');
    }
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/profile/import',
        queryParameters: {'mode': mode.toJson()},
        data: document,
      );
      return UserImportResult.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  /// Wipes the caller's routines, activities, measurements and custom
  /// exercises (`DELETE /profile/data`). Settings and the account stay.
  Future<ImportCounts> clearMyData() async {
    try {
      final response = await _dio.delete<Map<String, dynamic>>('/profile/data');
      return ImportCounts.fromJson(response.data!['deleted'] as Map<String, dynamic>);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }
}
