import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_info.dart';

/// Which releases "Check for updates" follows. GitHub's `releases/latest`
/// never returns a prerelease, so a nightly build checked against it only ever
/// saw the last stable -- and reported "latest version" while newer nightlies
/// existed. [nightly] follows the newest release of any kind.
enum UpdateChannel { stable, nightly }

/// Whether [version] (a `--dart-define APP_VERSION`, e.g. `1.3.3-nightly.20261106`
/// or a tag like `nightly-20261106`) is a nightly build.
bool isNightlyVersion(String version) => RegExp(r'nightly[-.]\d').hasMatch(version);

/// A running nightly follows nightlies; anything else starts on stable.
UpdateChannel defaultUpdateChannel([String version = appVersion]) =>
    isNightlyVersion(version) ? UpdateChannel.nightly : UpdateChannel.stable;

/// Persists an explicit channel choice, like `ThemeModeStorage`.
class UpdateChannelStorage {
  const UpdateChannelStorage();

  static const _key = 'update_channel';

  /// Null when nothing (or something unrecognised) is stored: use the default.
  Future<UpdateChannel?> read() async {
    try {
      final stored = (await SharedPreferences.getInstance()).getString(_key);
      return UpdateChannel.values.asNameMap()[stored];
    } catch (_) {
      return null;
    }
  }

  Future<void> write(UpdateChannel channel) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, channel.name);
    } catch (_) {
      // Best-effort: the choice still applies for this run.
    }
  }
}

final updateChannelStorageProvider = Provider<UpdateChannelStorage>(
  (ref) => const UpdateChannelStorage(),
);

/// The active channel; `main()` overrides the starting value from storage.
final updateChannelProvider = StateProvider<UpdateChannel>((ref) => defaultUpdateChannel());
