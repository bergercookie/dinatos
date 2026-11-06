import 'package:dinatos_frontend/core/update_channel.dart';
import 'package:dinatos_frontend/core/update_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isNewerVersion', () {
    test('compares numerically, not lexically', () {
      expect(isNewerVersion('1.10.0', '1.9.0'), isTrue);
      expect(isNewerVersion('1.9.0', '1.10.0'), isFalse);
      expect(isNewerVersion('2.0.0', '1.99.99'), isTrue);
      expect(isNewerVersion('0.1.1', '0.1.0'), isTrue);
    });

    test('equal versions are not newer', () {
      expect(isNewerVersion('1.2.3', '1.2.3'), isFalse);
    });

    test('tolerates a leading v and missing components', () {
      expect(isNewerVersion('v1.2.3', '1.2.3'), isFalse);
      expect(isNewerVersion('v1.3.0', '1.2.3'), isTrue);
      expect(isNewerVersion('V1.3', 'v1.2.9'), isTrue);
      expect(isNewerVersion('1.2', '1.2.0'), isFalse);
    });

    test('ignores build metadata', () {
      expect(isNewerVersion('1.2.3+7', '1.2.3'), isFalse);
    });

    test('a pre-release ranks below its release', () {
      expect(isNewerVersion('1.2.0', '1.2.0-rc.1'), isTrue);
      expect(isNewerVersion('1.2.0-rc.1', '1.2.0'), isFalse);
      expect(isNewerVersion('1.3.0-rc.1', '1.2.0'), isTrue);
    });

    test('is null when either side is not a version', () {
      expect(isNewerVersion('v1.0.0', 'dev'), isNull);
      expect(isNewerVersion('nightly', '1.0.0'), isNull);
      expect(isNewerVersion('', ''), isNull);
    });
  });

  group('evaluateUpdate', () {
    const release = LatestRelease(tag: 'v1.2.0', url: 'https://example.com/r');

    test('maps each outcome', () {
      expect(evaluateUpdate(release, '1.1.0'), isA<UpdateAvailable>());
      expect(evaluateUpdate(release, '1.2.0'), isA<UpToDate>());
      expect(evaluateUpdate(release, '1.3.0'), isA<UpToDate>());
      expect(evaluateUpdate(release, 'dev'), isA<UnknownCurrentVersion>());
      expect(evaluateUpdate(null, '1.2.0'), isA<NoReleasesYet>());
    });
  });

  group('nightlies', () {
    const nightly = LatestRelease(tag: 'nightly-20261106', url: 'https://example.com/n');

    test('a newer nightly is available to a running nightly', () {
      // The reported bug: stable v1.2.3 is "latest", the nightly is not.
      expect(evaluateUpdate(nightly, '1.3.3-nightly.20261105'), isA<UpdateAvailable>());
      expect(evaluateUpdate(nightly, '1.3.3-nightly.20261106'), isA<UpToDate>());
      expect(evaluateUpdate(nightly, '1.3.3-nightly.20261107'), isA<UpToDate>());
    });

    test('same-day rebuilds are ordered by their suffix', () {
      const rebuilt = LatestRelease(tag: 'nightly-20261106.2', url: 'u');
      expect(evaluateUpdate(rebuilt, '1.3.3-nightly.20261106'), isA<UpdateAvailable>());
      expect(evaluateUpdate(rebuilt, '1.3.3-nightly.20261106.2'), isA<UpToDate>());
      expect(evaluateUpdate(nightly, '1.3.3-nightly.20261106.2'), isA<UpToDate>());
    });

    test('a nightly is newer than a stable, and unknown for a dev build', () {
      expect(evaluateUpdate(nightly, '1.2.3'), isA<UpdateAvailable>());
      expect(evaluateUpdate(nightly, 'dev'), isA<UnknownCurrentVersion>());
    });

    test('a stable release supersedes the nightly it was built from', () {
      const stable = LatestRelease(tag: 'v1.3.3', url: 'u');
      expect(evaluateUpdate(stable, '1.3.3-nightly.20261106'), isA<UpdateAvailable>());
      expect(
        evaluateUpdate(const LatestRelease(tag: 'v1.2.3', url: 'u'), '1.3.3-nightly.20261106'),
        isA<UpToDate>(),
      );
    });
  });

  group('defaultUpdateChannel', () {
    test('follows nightly only when already on one', () {
      expect(defaultUpdateChannel('1.3.3-nightly.20261106'), UpdateChannel.nightly);
      expect(defaultUpdateChannel('1.2.3'), UpdateChannel.stable);
      expect(defaultUpdateChannel('dev'), UpdateChannel.stable);
    });
  });
}
