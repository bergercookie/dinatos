import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the person's [ThemeMode] choice. Plain `shared_preferences`
/// rather than the secure store the server URL uses: nothing sensitive here,
/// and it must not depend on a keyring being available.
class ThemeModeStorage {
  const ThemeModeStorage();

  static const _key = 'theme_mode';

  /// [ThemeMode.system] when nothing (or something unrecognised) is stored.
  Future<ThemeMode> read() async {
    try {
      final stored = (await SharedPreferences.getInstance()).getString(_key);
      return ThemeMode.values.asNameMap()[stored] ?? ThemeMode.system;
    } catch (_) {
      return ThemeMode.system;
    }
  }

  Future<void> write(ThemeMode mode) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, mode.name);
    } catch (_) {
      // Best-effort: the choice still applies for this run.
    }
  }
}

final themeModeStorageProvider = Provider<ThemeModeStorage>((ref) => const ThemeModeStorage());

/// The active theme mode. Defaults to following the system; `main()`
/// overrides the starting value from storage, like [serverUrlProvider].
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
