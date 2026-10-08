import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/dio_provider.dart';
import '../../models/planned_workout.dart';

final plannedWorkoutsRepositoryProvider = Provider<PlannedWorkoutsRepository>((ref) {
  return PlannedWorkoutsRepository(ref.watch(dioProvider));
});

/// Where the calendar feed lives: its secret [token], and the [path] to
/// append to the server's address. Both null while the feed is switched off.
class CalendarFeed {
  const CalendarFeed({this.token, this.path});

  factory CalendarFeed.fromJson(Map<String, dynamic> json) =>
      CalendarFeed(token: json['token'] as String?, path: json['path'] as String?);

  final String? token;
  final String? path;

  bool get enabled => token != null;
}

class PlannedWorkoutsRepository {
  PlannedWorkoutsRepository(this._dio);

  final Dio _dio;

  Future<List<PlannedWorkout>> list({DateTime? since, DateTime? until}) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/planned-workouts',
        queryParameters: {
          if (since != null) 'since': since.toUtc().toIso8601String(),
          if (until != null) 'until': until.toUtc().toIso8601String(),
        },
      );
      return response.data!.map((e) => PlannedWorkout.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<PlannedWorkout> get(int id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/planned-workouts/$id');
      return PlannedWorkout.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<PlannedWorkout> create(PlannedWorkout plan) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/planned-workouts',
        data: plan.toJson(),
      );
      return PlannedWorkout.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<PlannedWorkout> replace(int id, PlannedWorkout plan) async {
    try {
      final response = await _dio.put<Map<String, dynamic>>(
        '/planned-workouts/$id',
        data: plan.toJson(),
      );
      return PlannedWorkout.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _dio.delete<void>('/planned-workouts/$id');
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<CalendarFeed> feed() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/profile/calendar');
      return CalendarFeed.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  /// Turns the feed on -- or, if it already is, replaces its secret so the old link stops working.
  Future<CalendarFeed> enableFeed() async {
    try {
      final response = await _dio.post<Map<String, dynamic>>('/profile/calendar');
      return CalendarFeed.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<void> disableFeed() async {
    try {
      await _dio.delete<void>('/profile/calendar');
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }
}
