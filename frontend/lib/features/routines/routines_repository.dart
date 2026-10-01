import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/dio_provider.dart';
import '../../models/routine.dart';

final routinesRepositoryProvider = Provider<RoutinesRepository>((ref) {
  return RoutinesRepository(ref.watch(dioProvider));
});

class RoutinesRepository {
  RoutinesRepository(this._dio);

  final Dio _dio;

  Future<List<Routine>> list() async {
    try {
      final response = await _dio.get<List<dynamic>>('/routines');
      return response.data!.map((e) => Routine.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<Routine> get(int id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/routines/$id');
      return Routine.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<Routine> create(Routine routine) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>('/routines', data: routine.toJson());
      return Routine.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  /// `PUT` replaces the routine (and its exercises/sets) in full -- there is
  /// no endpoint for patching one set in isolation.
  Future<Routine> replace(int id, Routine routine) async {
    try {
      final response = await _dio.put<Map<String, dynamic>>(
        '/routines/$id',
        data: routine.toJson(),
      );
      return Routine.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _dio.delete<void>('/routines/$id');
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }
}
