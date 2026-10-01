import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/dio_provider.dart';
import '../../models/measurement.dart';

final measurementsRepositoryProvider = Provider<MeasurementsRepository>((ref) {
  return MeasurementsRepository(ref.watch(dioProvider));
});

class MeasurementsRepository {
  MeasurementsRepository(this._dio);

  final Dio _dio;

  Future<List<BodyMeasurement>> list() async {
    try {
      final response = await _dio.get<List<dynamic>>('/measurements');
      return response.data!
          .map((e) => BodyMeasurement.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<BodyMeasurement> get(int id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/measurements/$id');
      return BodyMeasurement.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<BodyMeasurement> create(BodyMeasurement measurement) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/measurements',
        data: measurement.toJson(),
      );
      return BodyMeasurement.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<BodyMeasurement> replace(int id, BodyMeasurement measurement) async {
    try {
      final response = await _dio.put<Map<String, dynamic>>(
        '/measurements/$id',
        data: measurement.toJson(),
      );
      return BodyMeasurement.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _dio.delete<void>('/measurements/$id');
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }
}
