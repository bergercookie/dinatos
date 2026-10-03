import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/dio_provider.dart';
import '../../models/equipment.dart';
import '../../models/exercise.dart';
import '../../models/exercise_records.dart';
import '../../models/exercise_tutorial.dart';
import '../../models/muscle_group.dart';

final exercisesRepositoryProvider = Provider<ExercisesRepository>((ref) {
  return ExercisesRepository(ref.watch(dioProvider));
});

/// One page of [ExercisesRepository.listPage], plus the true total row count
/// (over the whole search, not just this page) so a caller knows when it has
/// reached the end.
class ExercisePage {
  const ExercisePage({required this.items, required this.total});

  final List<Exercise> items;
  final int total;
}

/// Exercises are the one resource shared across every account (see
/// docs/architecture/domain-model.md's "Concepts") -- every other repository scopes
/// implicitly to the caller via the bearer token, same as this one, but
/// there's no per-user data here to scope.
class ExercisesRepository {
  ExercisesRepository(this._dio);

  final Dio _dio;

  Future<List<Exercise>> list({String? search, MuscleGroup? muscle, Equipment? equipment}) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/exercises',
        queryParameters: {
          if (search != null && search.isNotEmpty) 'search': search,
          if (muscle != null) 'muscle': muscle.toJson(),
          if (equipment != null) 'equipment': equipment.toJson(),
        },
      );
      return response.data!.map((e) => Exercise.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  /// A page of the catalog, for the exercises list screen's infinite scroll --
  /// unlike [list], this always passes `limit`/`offset`, so the backend
  /// slices the result and reports the true (pre-slice) count via the
  /// `X-Total-Count` header instead of returning everything in one shot.
  Future<ExercisePage> listPage({
    String? search,
    bool? isCustom,
    required int limit,
    required int offset,
  }) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/exercises',
        queryParameters: {
          if (search != null && search.isNotEmpty) 'search': search,
          'is_custom': ?isCustom,
          'limit': limit,
          'offset': offset,
        },
      );
      final items = response.data!
          .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
          .toList();
      final total = int.parse(response.headers.value('x-total-count') ?? '${items.length}');
      return ExercisePage(items: items, total: total);
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

  /// A tutorial image the backend proxies (a `gif_urls` entry that is a
  /// path on this server rather than an absolute URL, e.g. WorkoutX's,
  /// whose GIFs need the user's API key). Fetched through Dio so the
  /// bearer token goes along; `Image.network` can't send one.
  Future<Uint8List> getMedia(String path) async {
    try {
      final response = await _dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  /// This caller's own best weight/reps ever logged for this exercise --
  /// what the live workout summary compares a session's best set against to
  /// flag a new personal record.
  Future<ExerciseRecords> getRecords(int id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/exercises/$id/records');
      return ExerciseRecords.fromJson(response.data!);
    } on DioException catch (error) {
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
