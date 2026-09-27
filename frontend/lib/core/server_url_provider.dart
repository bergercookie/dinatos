import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_config.dart';
import 'server_url_storage.dart';

final serverUrlStorageProvider = Provider<ServerUrlStorage>((ref) => ServerUrlStorage());

/// The backend's base URL for this install, persisted across restarts.
/// [ApiConfig.baseUrl] (a build-time default, e.g. for local dev) is only
/// ever this provider's *starting* value -- `main()` overrides it with
/// whatever was last saved before the widget tree is built, so a released
/// binary handed to someone else is never stuck pointed at the machine that
/// built it.
///
/// [dioProvider] watches this, so changing it rebuilds every provider that
/// depends on the API client, [authNotifierProvider] included -- a session
/// token from one backend is meaningless on another, so switching servers
/// always means logging in again there (see the login and profile screens,
/// the two places this is edited).
final serverUrlProvider = StateProvider<String>((ref) => ApiConfig.baseUrl);
