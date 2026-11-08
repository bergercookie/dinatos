import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dio_provider.dart';

/// The version of the server this app talks to, from `GET /health`, or null
/// when the server can't be reached or is too old to report it.
///
/// Watches [dioProvider], so it asks again when the server URL changes.
final serverVersionProvider = FutureProvider.autoDispose<String?>((ref) async {
  try {
    final response = await ref.watch(dioProvider).get<Map<String, dynamic>>('/health');
    return response.data?['version'] as String?;
  } catch (_) {
    return null;
  }
});
