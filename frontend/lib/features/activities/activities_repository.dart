import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/dio_provider.dart';
import '../../models/activity.dart';

final activitiesRepositoryProvider = Provider<ActivitiesRepository>((ref) {
  return ActivitiesRepository(ref.watch(dioProvider));
});

class ActivitiesRepository {
  ActivitiesRepository(this._dio);

  final Dio _dio;

  Future<List<Activity>> list({DateTime? since, DateTime? until}) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/activities',
        queryParameters: {
          if (since != null) 'since': since.toUtc().toIso8601String(),
          if (until != null) 'until': until.toUtc().toIso8601String(),
        },
      );
      return response.data!.map((e) => Activity.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<Activity> get(int id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/activities/$id');
      return Activity.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<Activity> create(Activity activity) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/activities',
        data: activity.toJson(),
      );
      return Activity.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<Activity> replace(int id, Activity activity) async {
    try {
      final response = await _dio.put<Map<String, dynamic>>(
        '/activities/$id',
        data: activity.toJson(),
      );
      return Activity.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _dio.delete<void>('/activities/$id');
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }
}
