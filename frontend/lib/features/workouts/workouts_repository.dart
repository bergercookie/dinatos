import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/dio_provider.dart';
import '../../models/workout.dart';

final workoutsRepositoryProvider = Provider<WorkoutsRepository>((ref) {
  return WorkoutsRepository(ref.watch(dioProvider));
});

class WorkoutsRepository {
  WorkoutsRepository(this._dio);

  final Dio _dio;

  Future<List<Workout>> list() async {
    try {
      final response = await _dio.get<List<dynamic>>('/workouts');
      return response.data!.map((e) => Workout.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<Workout> get(int id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/workouts/$id');
      return Workout.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<Workout> create(Workout workout) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>('/workouts', data: workout.toJson());
      return Workout.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  /// `PUT` replaces the workout (and its exercises/sets) in full -- there is
  /// no endpoint for patching one set in isolation.
  Future<Workout> replace(int id, Workout workout) async {
    try {
      final response = await _dio.put<Map<String, dynamic>>(
        '/workouts/$id',
        data: workout.toJson(),
      );
      return Workout.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _dio.delete<void>('/workouts/$id');
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }
}
