import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/dio_provider.dart';
import '../../models/exercise.dart';
import '../../models/exercise_tutorial.dart';

final exercisesRepositoryProvider = Provider<ExercisesRepository>((ref) {
  return ExercisesRepository(ref.watch(dioProvider));
});

/// Exercises are the one resource shared across every account (see
/// docs/architecture/domain-model.md's "Concepts") -- every other repository scopes
/// implicitly to the caller via the bearer token, same as this one, but
/// there's no per-user data here to scope.
class ExercisesRepository {
  ExercisesRepository(this._dio);

  final Dio _dio;

  Future<List<Exercise>> list({String? search}) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/exercises',
        queryParameters: search != null && search.isNotEmpty ? {'search': search} : null,
      );
      return response.data!.map((e) => Exercise.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<Exercise> get(int id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/exercises/$id');
      return Exercise.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<Exercise> create(Exercise exercise) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>('/exercises', data: exercise.toJson());
      return Exercise.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<Exercise> update(int id, Exercise exercise) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/exercises/$id',
        data: exercise.toJson(),
      );
      return Exercise.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  /// `null` means the active provider has nothing for this exercise (the
  /// backend's 404) -- an ordinary, expected outcome for a person's own
  /// custom exercise, not an error; anything else (a real failure to
  /// reach the provider, a network error) still throws.
  Future<ExerciseTutorial?> getTutorial(int id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/exercises/$id/tutorial');
      return ExerciseTutorial.fromJson(response.data!);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      throw ApiException.fromDioException(error);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _dio.delete<void>('/exercises/$id');
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }
}
