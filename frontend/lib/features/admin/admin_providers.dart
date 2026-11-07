import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/admin_settings.dart';
import '../../models/user.dart';
import 'admin_repository.dart';

final adminUsersProvider = FutureProvider.autoDispose<List<User>>((ref) {
  return ref.watch(adminRepositoryProvider).listUsers();
});

final adminSettingsProvider = FutureProvider.autoDispose<AdminSettings>((ref) {
  return ref.watch(adminRepositoryProvider).getSettings();
});
