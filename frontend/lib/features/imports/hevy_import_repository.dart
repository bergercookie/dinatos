import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/dio_provider.dart';
import '../../models/hevy_import_result.dart';

final hevyImportRepositoryProvider = Provider<HevyImportRepository>((ref) {
  return HevyImportRepository(ref.watch(dioProvider));
});

/// The backend's 409: a file with this exact content (by hash, not
/// filename -- Hevy names every export the same thing) was already
/// imported. Callers get the chance to ask "import it again anyway?"
/// and retry with `force: true`, rather than just showing a generic error.
class HevyImportAlreadyDoneException implements Exception {
  const HevyImportAlreadyDoneException({this.previousFilename, this.previouslyImportedAt});

  final String? previousFilename;
  final String? previouslyImportedAt;
}

class HevyImportRepository {
  HevyImportRepository(this._dio);

  final Dio _dio;

  Future<HevyWorkoutImportResult> importWorkouts(
    List<int> bytes,
    String filename, {
    bool force = false,
  }) async {
    final data = await _upload('/imports/hevy/workouts', bytes, filename, force: force);
    return HevyWorkoutImportResult.fromJson(data);
  }

  Future<HevyMeasurementImportResult> importMeasurements(
    List<int> bytes,
    String filename, {
    bool force = false,
  }) async {
    final data = await _upload('/imports/hevy/measurements', bytes, filename, force: force);
    return HevyMeasurementImportResult.fromJson(data);
  }

  Future<Map<String, dynamic>> _upload(
    String path,
    List<int> bytes,
    String filename, {
    required bool force,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        path,
        queryParameters: {'force': force},
        data: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)}),
      );
      return response.data!;
    } on DioException catch (error) {
      throw _translate(error);
    }
  }

  Exception _translate(DioException error) {
    if (error.response?.statusCode == 409) {
      final detail = error.response?.data is Map ? error.response!.data['detail'] : null;
      return HevyImportAlreadyDoneException(
        previousFilename: detail is Map ? detail['previous_filename'] as String? : null,
        previouslyImportedAt: detail is Map ? detail['previously_imported_at'] as String? : null,
      );
    }
    return ApiException.fromDioException(error);
  }
}
