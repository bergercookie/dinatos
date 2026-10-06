import 'package:shared_preferences/shared_preferences.dart';

/// Where the no-server mode keeps everything: one JSON document (settings,
/// custom exercises, routines, activities, measurements) in a single string.
/// An interface so tests can use memory and not the platform.
abstract class LocalDocumentStorage {
  Future<String?> read();
  Future<void> write(String document);
  Future<void> clear();
}

/// `shared_preferences`: on Android a private file only this app can read,
/// removed with the app (or its data) -- see docs/user-guide/local-mode.md
/// for what that means for the person.
class PrefsLocalDocumentStorage implements LocalDocumentStorage {
  const PrefsLocalDocumentStorage();

  static const _key = 'local_data_v1';

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String document) async {
    await (await SharedPreferences.getInstance()).setString(_key, document);
  }

  @override
  Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove(_key);
  }
}

class MemoryLocalDocumentStorage implements LocalDocumentStorage {
  MemoryLocalDocumentStorage([this.document]);

  String? document;

  @override
  Future<String?> read() async => document;

  @override
  Future<void> write(String value) async => document = value;

  @override
  Future<void> clear() async => document = null;
}
