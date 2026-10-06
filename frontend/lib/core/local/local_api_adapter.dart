import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'local_api.dart';

/// Lets a plain `Dio` talk to [LocalApi] instead of the network -- the whole
/// no-server mode is this one seam, so no repository or screen knows which
/// mode it is in.
class LocalApiAdapter implements HttpClientAdapter {
  LocalApiAdapter(this._api);

  final LocalApi _api;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // Round-tripped through JSON so a request body is exactly what the
    // server would have parsed (and later edits to the caller's own maps
    // cannot reach the stored data).
    final data = options.data;
    final body = data == null ? null : jsonDecode(jsonEncode(data));
    final response = await _api.handle(options.method, options.uri, body);
    final bytes = utf8.encode(response.body == null ? '' : jsonEncode(response.body));
    return ResponseBody.fromBytes(
      bytes,
      response.status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        for (final entry in response.headers.entries) entry.key: [entry.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
