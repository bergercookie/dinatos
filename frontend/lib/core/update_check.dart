import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_info.dart';

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

/// Compares [latest] (null: the project has no release yet) with [current].
UpdateCheckResult evaluateUpdate(LatestRelease? latest, String current) {
  if (latest == null) return const NoReleasesYet();
  return switch (isNewerVersion(latest.tag, current)) {
    true => UpdateAvailable(latest),
    false => const UpToDate(),
    null => UnknownCurrentVersion(latest),
  };
}

const latestReleaseApiUrl = 'https://api.github.com/repos/bergercookie/dinatos/releases/latest';

/// Fetches the latest GitHub release, or null if there is none (the API's 404).
/// Throws on anything else (offline, rate limited, ...). A provider so tests
/// can replace it.
///
/// A plain [Dio], deliberately not `dioProvider`: that one points at the
/// user's own backend and its auth interceptor would send their bearer token
/// to GitHub. api.github.com allows cross-origin requests, so the web build
/// can call it directly.
final latestReleaseFetcherProvider = Provider<Future<LatestRelease?> Function()>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Accept': 'application/vnd.github+json'},
      validateStatus: (status) => status != null && (status < 300 || status == 404),
    ),
  );
  return () async {
    final response = await dio.get<Map<String, dynamic>>(latestReleaseApiUrl);
    if (response.statusCode == 404) return null;
    final data = response.data;
    final tag = data?['tag_name'];
    final url = data?['html_url'];
    if (tag is! String || url is! String) {
      throw const FormatException('unexpected release payload');
    }
    return LatestRelease(tag: tag, url: url);
  };
});

/// Looks up the latest release and compares it with the running [appVersion];
/// never throws -- any failure is [UpdateCheckFailed].
final updateCheckProvider = Provider<Future<UpdateCheckResult> Function()>((ref) {
  final fetch = ref.watch(latestReleaseFetcherProvider);
  return () async {
    try {
      return evaluateUpdate(await fetch(), appVersion);
    } on Exception {
      return const UpdateCheckFailed();
    }
  };
});
