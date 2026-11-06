import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_info.dart';
import 'update_channel.dart';

/// Parses a version like `v1.2.3`, `1.2`, `1.2.3-rc.1` or `1.2.3+45` into
/// numeric `[major, minor, patch]` plus whether it is a pre-release, or null
/// if it doesn't look like a version at all (the `dev` default of
/// [appVersion], for one). Build metadata (`+...`) is ignored, as semver says.
({List<int> core, bool preRelease})? _parseVersion(String raw) {
  final match = RegExp(
    r'^[vV]?(\d+)(?:\.(\d+))?(?:\.(\d+))?(-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
  ).firstMatch(raw.trim());
  if (match == null) return null;
  return (
    core: [for (var i = 1; i <= 3; i++) int.tryParse(match.group(i) ?? '0') ?? 0],
    preRelease: match.group(4) != null,
  );
}

/// Whether [latest] is a strictly newer version than [current], semver-ish:
/// numeric `major.minor.patch` comparison, a leading `v` tolerated, and a
/// pre-release (`1.2.0-rc.1`) ranked below its own release (`1.2.0`) but not
/// ordered against another pre-release of the same version. Null when either
/// side isn't a parseable version (a `dev` build), so a caller can tell
/// "not newer" from "can't tell".
bool? isNewerVersion(String latest, String current) {
  final a = _parseVersion(latest);
  final b = _parseVersion(current);
  if (a == null || b == null) return null;
  for (var i = 0; i < 3; i++) {
    if (a.core[i] != b.core[i]) return a.core[i] > b.core[i];
  }
  return b.preRelease && !a.preRelease;
}

/// The newest published release: its tag (e.g. `v1.2.0`) and web page.
class LatestRelease {
  const LatestRelease({required this.tag, required this.url});

  final String tag;
  final String url;
}

/// What a "Check for updates" press found.
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

class UpToDate extends UpdateCheckResult {
  const UpToDate();
}

class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable(this.release);

  final LatestRelease release;
}

/// A release exists but this build's version can't be ordered against it
/// (a local `dev` build): shown as information, not as "update available".
class UnknownCurrentVersion extends UpdateCheckResult {
  const UnknownCurrentVersion(this.release);

  final LatestRelease release;
}

class NoReleasesYet extends UpdateCheckResult {
  const NoReleasesYet();
}

class UpdateCheckFailed extends UpdateCheckResult {
  const UpdateCheckFailed();
}

/// `(date, n)` of a nightly's `nightly-YYYYMMDD[.n]` tag or
/// `<base>-nightly.YYYYMMDD[.n]` version, or null if it isn't a nightly.
/// Nightlies on the same date are numbered `.2`, `.3`, ... (see nightly.yml).
({int date, int n})? _nightlyStamp(String raw) {
  final match = RegExp(r'nightly[-.](\d{8})(?:\.(\d+))?').firstMatch(raw);
  if (match == null) return null;
  return (date: int.parse(match.group(1)!), n: int.tryParse(match.group(2) ?? '') ?? 1);
}

/// Compares [latest] (null: the project has no release yet) with [current].
///
/// A nightly [latest] is ordered by its date stamp against a nightly
/// [current]; against a stable [current] it is newer, since the release list
/// is newest-first and a stable newer than it would have been picked instead.
UpdateCheckResult evaluateUpdate(LatestRelease? latest, String current) {
  if (latest == null) return const NoReleasesYet();
  final latestStamp = _nightlyStamp(latest.tag);
  if (latestStamp != null) {
    final currentStamp = _nightlyStamp(current);
    if (currentStamp != null) {
      final newer = latestStamp.date != currentStamp.date
          ? latestStamp.date > currentStamp.date
          : latestStamp.n > currentStamp.n;
      return newer ? UpdateAvailable(latest) : const UpToDate();
    }
    return _parseVersion(current) == null ? UnknownCurrentVersion(latest) : UpdateAvailable(latest);
  }
  return switch (isNewerVersion(latest.tag, current)) {
    true => UpdateAvailable(latest),
    false => const UpToDate(),
    null => UnknownCurrentVersion(latest),
  };
}

const latestReleaseApiUrl = 'https://api.github.com/repos/bergercookie/dinatos/releases/latest';

/// Newest-first list, prereleases (nightlies) included -- `releases/latest`
/// skips them.
const releasesApiUrl = 'https://api.github.com/repos/bergercookie/dinatos/releases?per_page=10';

LatestRelease _releaseFrom(Object? data) {
  final map = data is Map ? data : const {};
  final tag = map['tag_name'];
  final url = map['html_url'];
  if (tag is! String || url is! String) {
    throw const FormatException('unexpected release payload');
  }
  return LatestRelease(tag: tag, url: url);
}

/// Fetches the newest release on [UpdateChannel] -- the latest stable, or the
/// newest of any kind for nightly -- or null if there is none (the API's
/// 404, or an empty list). Throws on anything else (offline, rate limited,
/// ...). A provider so tests can replace it.
///
/// A plain [Dio], deliberately not `dioProvider`: that one points at the
/// user's own backend and its auth interceptor would send their bearer token
/// to GitHub. api.github.com allows cross-origin requests, so the web build
/// can call it directly.
final latestReleaseFetcherProvider = Provider<Future<LatestRelease?> Function(UpdateChannel)>((
  ref,
) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Accept': 'application/vnd.github+json'},
      validateStatus: (status) => status != null && (status < 300 || status == 404),
    ),
  );
  return (channel) async {
    if (channel == UpdateChannel.nightly) {
      final response = await dio.get<List<dynamic>>(releasesApiUrl);
      final releases = (response.data ?? const []).whereType<Map>().where(
        (release) => release['draft'] != true,
      );
      return releases.isEmpty ? null : _releaseFrom(releases.first);
    }
    final response = await dio.get<Map<String, dynamic>>(latestReleaseApiUrl);
    if (response.statusCode == 404) return null;
    return _releaseFrom(response.data);
  };
});

/// Looks up the latest release on the chosen [updateChannelProvider] and
/// compares it with the running [appVersion]; never throws -- any failure is
/// [UpdateCheckFailed].
final updateCheckProvider = Provider<Future<UpdateCheckResult> Function()>((ref) {
  final fetch = ref.watch(latestReleaseFetcherProvider);
  return () async {
    try {
      return evaluateUpdate(await fetch(ref.read(updateChannelProvider)), appVersion);
    } on Exception {
      return const UpdateCheckFailed();
    }
  };
});
