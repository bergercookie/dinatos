import 'package:dinatos_frontend/core/app_info.dart';
import 'package:dinatos_frontend/core/external_link.dart';
import 'package:dinatos_frontend/core/update_check.dart';
import 'package:dinatos_frontend/features/profile/about_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the GitHub project row opens the repository in a new tab', (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          urlOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
        child: const MaterialApp(home: AboutScreen()),
      ),
    );

    expect(find.text('Software version'), findsOneWidget);
    // flutter test is not a browser served by the backend, so the client row shows.
    expect(find.text('App version'), findsOneWidget);
    expect(find.text(githubUrl), findsOneWidget);

    await tester.tap(find.text('GitHub project'));
    await tester.pump();

    expect(opened, [Uri.parse('https://github.com/bergercookie/dinatos')]);
  });

  testWidgets('the Documentation row opens the docs in a new tab', (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          urlOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
        child: const MaterialApp(home: AboutScreen()),
      ),
    );

    await tester.tap(find.text('Documentation'));
    await tester.pump();

    expect(opened, [Uri.parse(docsUrl)]);
  });

  group('check for updates', () {
    // `appVersion` is 'dev' under `flutter test` (no --dart-define), so these
    // drive the screen through `updateCheckProvider` directly where the
    // running version matters.
    Future<void> pumpWith(
      WidgetTester tester, {
      required Future<UpdateCheckResult> Function() check,
      List<Uri>? opened,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            updateCheckProvider.overrideWithValue(check),
            urlOpenerProvider.overrideWithValue((uri) async {
              opened?.add(uri);
              return true;
            }),
          ],
          child: const MaterialApp(home: AboutScreen()),
        ),
      );
      await tester.tap(find.text('Check for updates'));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('says when up to date', (tester) async {
      await pumpWith(tester, check: () async => const UpToDate());
      expect(find.text('You are on the latest version'), findsOneWidget);
    });

    testWidgets('offers a link to the newer release', (tester) async {
      final opened = <Uri>[];
      await pumpWith(
        tester,
        opened: opened,
        check: () async => const UpdateAvailable(
          LatestRelease(
            tag: 'v9.9.9',
            url: 'https://github.com/bergercookie/dinatos/releases/tag/v9.9.9',
          ),
        ),
      );
      expect(find.text('Version v9.9.9 is available'), findsOneWidget);

      await tester.tap(find.text('Check for updates'));
      await tester.pump();
      expect(opened, [Uri.parse('https://github.com/bergercookie/dinatos/releases/tag/v9.9.9')]);
    });

    testWidgets('says when there are no releases yet', (tester) async {
      await pumpWith(tester, check: () async => const NoReleasesYet());
      expect(find.text('No releases have been published yet'), findsOneWidget);
    });

    testWidgets('says when the check failed, and can be retried', (tester) async {
      var calls = 0;
      await pumpWith(
        tester,
        check: () async {
          calls++;
          return calls == 1 ? const UpdateCheckFailed() : const UpToDate();
        },
      );
      expect(find.textContaining("Couldn't check"), findsOneWidget);

      await tester.tap(find.text('Check for updates'));
      await tester.pump();
      await tester.pump();
      expect(find.text('You are on the latest version'), findsOneWidget);
    });

    test('updateCheckProvider turns a fetch failure into UpdateCheckFailed', () async {
      final container = ProviderContainer(
        overrides: [
          latestReleaseFetcherProvider.overrideWithValue(() async => throw Exception('offline')),
        ],
      );
      addTearDown(container.dispose);
      expect(await container.read(updateCheckProvider)(), isA<UpdateCheckFailed>());
    });
  });
}
