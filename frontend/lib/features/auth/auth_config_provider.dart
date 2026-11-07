import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dio_provider.dart';

/// Whether the server currently accepts self-registration (the admin's switch,
/// or `DINATOS_ALLOW_REGISTRATION` when the operator set it; always true while
/// the server has no accounts).
///
/// Watches [dioProvider], so it re-asks whenever the login screen's server
/// URL changes. Anything that goes wrong (an older server without the
/// endpoint, or an unreachable one) counts as "enabled": this only decides
/// whether to *show* the Register link, the server enforces the real rule.
final registrationEnabledProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    final response = await ref.watch(dioProvider).get<Map<String, dynamic>>('/auth/config');
    return response.data!['registration_enabled'] as bool? ?? true;
  } catch (_) {
    return true;
  }
});
