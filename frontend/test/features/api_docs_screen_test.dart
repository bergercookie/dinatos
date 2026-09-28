import 'package:dinatos_frontend/core/server_url_provider.dart';
import 'package:dinatos_frontend/features/docs/api_docs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Installs a fake `Clipboard.setData` platform handler and records what was
/// asked to be copied, since the real one isn't available under `flutter test`.
({List<String> copied, void Function() restore}) _fakeClipboard({bool succeed = true}) {
  final copied = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        final data = (call.arguments as Map)['text'] as String;
        if (!succeed) throw PlatformException(code: 'unavailable');
        copied.add(data);
        return null;
      }
      return null;
    },
  );
  return (
    copied: copied,
    restore: () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );
}

void main() {
  Future<void> pumpScreen(WidgetTester tester, String serverUrl) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [serverUrlProvider.overrideWith((ref) => serverUrl)],
        child: const MaterialApp(home: ApiDocsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers the backend Swagger URL derived from the configured server', (tester) async {
    // `flutter test` runs on the VM, so this exercises the *stub* half of the
    // conditional import -- the same fallback a native target gets, and the
    // one that keeps the web build from ever showing a blank frame.
    await pumpScreen(tester, 'https://api.example.com');

    expect(find.text('API documentation'), findsOneWidget);
    expect(find.text('https://api.example.com/docs'), findsOneWidget);
    // The other two views of the same schema, so the page is useful even when
    // the frame can't be shown.
    expect(find.text('https://api.example.com/redoc'), findsOneWidget);
    expect(find.text('https://api.example.com/openapi.json'), findsOneWidget);
  });

  testWidgets('follows a server URL with a trailing slash and a path prefix', (tester) async {
    await pumpScreen(tester, 'https://host/api/');

    expect(find.text('https://host/api/docs'), findsOneWidget);
  });

  testWidgets('copying the docs link reports success', (tester) async {
    final clipboard = _fakeClipboard();
    addTearDown(clipboard.restore);
    await pumpScreen(tester, 'https://api.example.com');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Copy link'));
    await tester.pumpAndSettle();

    expect(clipboard.copied, ['https://api.example.com/docs']);
    expect(find.text('Link copied'), findsOneWidget);
  });

  testWidgets('a failing clipboard is reported, not thrown', (tester) async {
    // An unhandled async error here would surface as a test failure far from
    // its cause; the button is supposed to degrade to a message instead.
    // `takeException` is the real assertion -- the message is the visible half.
    final clipboard = _fakeClipboard(succeed: false);
    addTearDown(clipboard.restore);
    await pumpScreen(tester, 'https://api.example.com');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Copy link'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Could not copy'), findsOneWidget);
  });
}
