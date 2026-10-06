import 'package:dinatos_frontend/core/api_exception.dart';
import 'package:dinatos_frontend/features/api_keys/api_keys_repository.dart';
import 'package:dinatos_frontend/features/api_keys/api_keys_screen.dart';
import 'package:dinatos_frontend/models/api_key.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockApiKeysRepository extends Mock implements ApiKeysRepository {}

ApiKeySummary _key(int id, String name, {DateTime? lastUsed}) => ApiKeySummary(
  id: id,
  name: name,
  suffix: 'x$id'.padRight(3, 'z'),
  createdAt: DateTime.utc(2026, 10, 1),
  lastUsedAt: lastUsed,
);

void main() {
  late MockApiKeysRepository repository;
  late List<ApiKeySummary> stored;
  String? clipboard;

  setUp(() {
    repository = MockApiKeysRepository();
    stored = [_key(1, 'Laptop', lastUsed: DateTime.utc(2026, 10, 3)), _key(2, 'Script')];
    when(() => repository.list()).thenAnswer((_) async => List.of(stored));
    when(() => repository.delete(any())).thenAnswer((invocation) async {
      stored.removeWhere((k) => k.id == invocation.positionalArguments.single);
    });
    clipboard = null;
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiKeysRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: ApiKeysScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists keys by name and last characters only, never the key', (tester) async {
    await pump(tester);
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.textContaining('dnk_…x1z'), findsOneWidget);
    expect(find.textContaining('never used'), findsOneWidget);
    expect(find.textContaining('last used'), findsOneWidget);
  });

  testWidgets('a new key is named, shown once with a warning, and can be copied', (tester) async {
    when(() => repository.create('Claude MCP')).thenAnswer((_) async {
      final summary = _key(3, 'Claude MCP');
      stored.add(summary);
      return CreatedApiKey(summary: summary, key: 'dnk_SECRETSECRETSECRET');
    });
    await pump(tester);

    await tester.tap(find.text('Create key'));
    await tester.pumpAndSettle();
    // The Create button is disabled until there is a name.
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create')).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), 'Claude MCP');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(find.text('dnk_SECRETSECRETSECRET'), findsOneWidget);
    expect(find.textContaining('only time it is shown'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(clipboard, 'dnk_SECRETSECRETSECRET');

    await tester.tap(find.text("I've saved it"));
    await tester.pumpAndSettle();
    // Gone for good: the list shows the new key by its name and tail only.
    expect(find.text('dnk_SECRETSECRETSECRET'), findsNothing);
    expect(find.text('Claude MCP'), findsOneWidget);
    expect(find.textContaining('dnk_…x3z'), findsOneWidget);
  });

  testWidgets('a key is deleted only after confirming', (tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip('Delete Laptop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    verifyNever(() => repository.delete(any()));
    expect(find.text('Laptop'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete Laptop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete key'));
    await tester.pumpAndSettle();
    verify(() => repository.delete(1)).called(1);
    expect(find.text('Laptop'), findsNothing);
  });

  testWidgets('a failed creation is reported', (tester) async {
    when(() => repository.create(any())).thenThrow(const ApiException('at most 25 API keys'));
    await pump(tester);
    await tester.tap(find.text('Create key'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'One more');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.textContaining('at most 25 API keys'), findsOneWidget);
  });

  testWidgets('an empty list says how to start', (tester) async {
    stored.clear();
    await pump(tester);
    expect(find.text('No API keys yet'), findsOneWidget);
  });
}
