import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/dio_provider.dart';
import '../../core/file_io.dart';
import '../../models/data_transfer_result.dart';
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

  /// The whole server as one JSON file (`GET /admin/backup`). It contains
  /// password hashes and API keys -- callers should say so.
  Future<FileContent> downloadBackup() async {
    try {
      final response = await _dio.get<List<int>>(
        '/admin/backup',
        options: Options(responseType: ResponseType.bytes),
      );
      return FileContent(
        filenameFromContentDisposition(
          response.headers.value('content-disposition'),
          'dinatos-backup.json',
        ),
        Uint8List.fromList(response.data!),
      );
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  /// Replaces *everything* on the server with [backup]
  /// (`POST /admin/backup/restore`). `confirm=true` is always sent: the
  /// confirmation that matters is the dialog in front of calling this.
  Future<BackupRestoreResult> restoreBackup(FileContent backup) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/admin/backup/restore',
        data: FormData.fromMap({
          'confirm': 'true',
          'file': MultipartFile.fromBytes(backup.bytes, filename: backup.name),
        }),
      );
      return BackupRestoreResult.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }
}
