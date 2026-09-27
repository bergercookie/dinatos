import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/profile.dart';
import 'profile_repository.dart';

final profileProvider = FutureProvider.autoDispose<Profile>((ref) {
  return ref.watch(profileRepositoryProvider).get();
});
