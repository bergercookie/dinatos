import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_api_provider.dart';
import 'local_mode.dart';

/// Switches this install to local (no-server) mode. Whatever was stored on the
/// device before is simply there again.
Future<void> enterLocalMode(WidgetRef ref) async {
  final storage = ref.read(localModeStorageProvider);
  await storage.writeMode(true);
  await storage.writePendingImport(false);
  ref.read(pendingLocalImportProvider.notifier).state = false;
  ref.read(localModeProvider.notifier).state = true;
}

/// Leaves local mode for a server. The data stays on the device (it is only
/// removed by "Clear all account data" or by uninstalling), and the login and
/// register screens remind the person to import their exported file.
Future<void> leaveLocalMode(WidgetRef ref) async {
  final storage = ref.read(localModeStorageProvider);
  await storage.writeMode(false);
  await storage.writePendingImport(true);
  ref.read(pendingLocalImportProvider.notifier).state = true;
  ref.read(localModeProvider.notifier).state = false;
}

/// The reminder has done its job (the file was imported, or it was dismissed).
Future<void> clearPendingLocalImport(WidgetRef ref) async {
  await ref.read(localModeStorageProvider).writePendingImport(false);
  ref.read(pendingLocalImportProvider.notifier).state = false;
}

/// Wipes everything the app keeps for local mode -- used by tests; the app
/// itself offers only "Clear all account data".
Future<void> eraseLocalData(WidgetRef ref) => ref.read(localDocumentStorageProvider).clear();
