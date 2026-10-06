import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether this install runs without a server: every request the app makes is
/// answered on the device (see `LocalApi`) and nobody logs in. Chosen on the
/// login screen, undone from Settings; `main()` restores it before the first
/// frame, the same way as the server URL.
final localModeProvider = StateProvider<bool>((ref) => false);

/// Set when someone leaves local mode for a server, until they have loaded
/// their exported file there (or dismissed the reminder): the login and
/// register screens show the "now import your file" steps while it is set.
final pendingLocalImportProvider = StateProvider<bool>((ref) => false);

final localModeStorageProvider = Provider<LocalModeStorage>((ref) => const LocalModeStorage());

class LocalModeStorage {
  const LocalModeStorage();

  static const _modeKey = 'local_mode';
  static const _pendingKey = 'local_pending_import';

  Future<bool> readMode() async =>
      (await SharedPreferences.getInstance()).getBool(_modeKey) ?? false;

  Future<void> writeMode(bool value) async {
    await (await SharedPreferences.getInstance()).setBool(_modeKey, value);
  }

  Future<bool> readPendingImport() async =>
      (await SharedPreferences.getInstance()).getBool(_pendingKey) ?? false;

  Future<void> writePendingImport(bool value) async {
    await (await SharedPreferences.getInstance()).setBool(_pendingKey, value);
  }
}
