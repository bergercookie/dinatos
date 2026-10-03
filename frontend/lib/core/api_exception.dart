import 'package:dio/dio.dart';

/// A backend error turned into something screens can show directly, instead
/// of every screen having to know Dio's exception shape.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  factory ApiException.fromDioException(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      return ApiException(data['detail'] as String, statusCode: error.response?.statusCode);
    }
    // A list: a 422 from request validation (`[{loc, msg, ...}]`), or from the
    // backup restore (`[String, ...]`) -- one line each, rather than "Unexpected error."
    if (data is Map && data['detail'] is List && (data['detail'] as List).isNotEmpty) {
      final lines = (data['detail'] as List).map(
        (item) => item is Map && item['msg'] is String ? item['msg'] as String : item.toString(),
      );
      return ApiException(lines.join('\n'), statusCode: error.response?.statusCode);
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return const ApiException('Could not reach the server.');
    }
    return ApiException(
      error.message ?? 'Unexpected error.',
      statusCode: error.response?.statusCode,
    );
  }

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;

  @override
  String toString() => message;
}
