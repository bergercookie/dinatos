import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/api_key.dart';
import 'api_keys_repository.dart';

final apiKeyListProvider = FutureProvider.autoDispose<List<ApiKeySummary>>((ref) {
  return ref.watch(apiKeysRepositoryProvider).list();
});
