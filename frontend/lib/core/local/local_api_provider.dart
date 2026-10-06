import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_info.dart';
import 'local_api.dart';
import 'local_document_storage.dart';

final localDocumentStorageProvider = Provider<LocalDocumentStorage>(
  (ref) => const PrefsLocalDocumentStorage(),
);

Future<List<Map<String, dynamic>>> _loadBundledCatalog() async {
  final raw = await rootBundle.loadString('assets/exercise_catalog.json');
  return (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
}

/// The on-device API, one instance for the whole app: it keeps the loaded
/// document in memory and serialises requests, so it must not be rebuilt
/// each time something else is.
final localApiProvider = Provider<LocalApi>((ref) {
  return LocalApi(
    storage: ref.watch(localDocumentStorageProvider),
    loadCatalog: _loadBundledCatalog,
    appVersion: appVersion,
  );
});
