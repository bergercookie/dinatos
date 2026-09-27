import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'insecure_tls_storage.dart';

final insecureTlsStorageProvider = Provider<InsecureTlsStorage>((ref) => InsecureTlsStorage());

/// Whether to skip TLS certificate verification for [serverUrlProvider]'s
/// current server. Off by default -- deliberately opt-in, since it's a
/// real reduction in security (any network path can then impersonate the
/// server), not just a convenience. `main()` overrides the starting value
/// from storage the same way it does for [serverUrlProvider]; [dioProvider]
/// watches this to actually wire it into the HTTP client.
final allowInsecureTlsProvider = StateProvider<bool>((ref) => false);
