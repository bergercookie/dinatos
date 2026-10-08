import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/dio_provider.dart';
import '../../models/intervals_import.dart';

final intervalsImportRepositoryProvider = Provider<IntervalsImportRepository>((ref) {
  return IntervalsImportRepository(ref.watch(dioProvider));
});

/// The backend's 409: some of the chosen activities were already imported
/// from Intervals.icu. Callers get the chance to ask "import them again
/// anyway?" and retry with `force: true` -- the same flow as re-uploading an
/// identical Hevy file -- rather than just showing a generic error.
class IntervalsAlreadyImportedException implements Exception {
  const IntervalsAlreadyImportedException(this.activityIds);

  final List<String> activityIds;
}

class IntervalsImportRepository {
  IntervalsImportRepository(this._dio);

  final Dio _dio;

  Map<String, dynamic> _source(String athleteId, String apiKey, DateTime oldest, DateTime newest) =>
      {
        'athlete_id': athleteId,
        'api_key': apiKey,
        'oldest': _date(oldest),
        'newest': _date(newest),
      };

  static String _date(DateTime value) => value.toIso8601String().substring(0, 10);

  Future<List<IntervalsActivity>> preview({
    required String athleteId,
    required String apiKey,
    required DateTime oldest,
    required DateTime newest,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/imports/intervals/preview',
        data: _source(athleteId, apiKey, oldest, newest),
      );
      return (response.data!['activities'] as List<dynamic>)
          .map((item) => IntervalsActivity.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw _translate(error);
    }
  }

  /// Imports [activityIds] out of the same window the preview was fetched for.
  Future<IntervalsImportResult> import({
    required String athleteId,
    required String apiKey,
    required DateTime oldest,
    required DateTime newest,
    required List<String> activityIds,
    bool force = false,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/imports/intervals/activities',
        queryParameters: {'force': force},
        data: {..._source(athleteId, apiKey, oldest, newest), 'activity_ids': activityIds},
      );
      return IntervalsImportResult.fromJson(response.data!);
    } on DioException catch (error) {
      throw _translate(error);
    }
  }

  Exception _translate(DioException error) {
    final data = error.response?.data;
    final detail = data is Map ? data['detail'] : null;
    if (error.response?.statusCode == 409 && detail is Map) {
      final already = detail['already_imported'];
      return IntervalsAlreadyImportedException(
        already is Map ? already.keys.cast<String>().toList() : const [],
      );
    }
    // 422 for ids that are gone/unimportable: the detail is an object with a message.
    if (detail is Map && detail['message'] is String) {
      return ApiException(detail['message'] as String, statusCode: error.response?.statusCode);
    }
    return ApiException.fromDioException(error);
  }
}
