import 'package:dinatos_frontend/features/activities/live/bulk_add_sheet.dart';
import 'package:dinatos_frontend/features/activities/live/speech_input.dart';
import 'package:dinatos_frontend/models/exercise.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _catalog = [
  Exercise(id: 1, name: 'Bench Press'),
  Exercise(id: 2, name: 'Crossover Reverse Lunge'),
  Exercise(id: 3, name: 'Pull-up'),
  Exercise(id: 4, name: 'Cable Row'),
];

class _FakeSpeech implements SpeechInput {
  _FakeSpeech({this.supported = true, this.error});

  final bool supported;
  final String? error;
  void Function(String)? onText;
  VoidCallback? onDone;
  bool stopped = false;

  @override
  bool get isSupported => supported;

  @override
  Future<String?> start({
    required void Function(String text) onText,
    required VoidCallback onDone,
  }) async {
    this.onText = onText;
    this.onDone = onDone;
    return error;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    onDone?.call();
  }
}

/// Opens the sheet from a button and records what it resolves with.
Future<List<List<Exercise>?>> _open(WidgetTester tester, _FakeSpeech speech) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final results = <List<Exercise>?>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [speechInputProvider.overrideWithValue(speech)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async =>
                results.add(await showBulkAddSheet(context, exercises: _catalog)),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('explains what to do before anything is entered', (tester) async {
    await _open(tester, _FakeSpeech());

    expect(find.textContaining('1. Say or type your exercises'), findsOneWidget);
    expect(find.textContaining('2. Check the matches'), findsOneWidget);
    expect(find.textContaining('3. Tap the button'), findsOneWidget);
    expect(find.text('Tap and speak'), findsOneWidget);
    expect(find.text('Check what we understood'), findsNothing);
    // Nothing to add yet, so the button is disabled.
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add exercises')).onPressed,
      isNull,
    );
  });

  testWidgets('without speech support there is no microphone and the text says to type', (
    tester,
  ) async {
    await _open(tester, _FakeSpeech(supported: false));

    expect(find.text('Tap and speak'), findsNothing);
    expect(find.textContaining('1. Type your exercises'), findsOneWidget);
  });

  testWidgets('a numbered list becomes one reviewable row per exercise', (tester) async {
    final results = await _open(tester, _FakeSpeech());

    await tester.enterText(find.byType(TextField), '1 reverse lunges 2 bench press 3 zzzz');
    await tester.pumpAndSettle();

    expect(find.text('Check what we understood'), findsOneWidget);
    expect(find.text('Crossover Reverse Lunge'), findsOneWidget);
    expect(find.text('You said "reverse lunges"'), findsOneWidget);
    expect(find.text('Best guess -- please check'), findsOneWidget);
    expect(find.text('Matched'), findsOneWidget);
    expect(find.text('No match -- tap to search'), findsOneWidget);
    // The unmatched one is not ticked, so two are added.
    expect(find.text('Add 2 exercises'), findsOneWidget);

    await tester.tap(find.text('Add 2 exercises'));
    await tester.pumpAndSettle();
    expect(results.single!.map((e) => e.id), [2, 1]);
  });

  testWidgets('unticking a row leaves it out', (tester) async {
    final results = await _open(tester, _FakeSpeech());
    await tester.enterText(find.byType(TextField), '1 bench press 2 pull ups');
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('Add 1 exercise'), findsOneWidget);

    await tester.tap(find.text('Add 1 exercise'));
    await tester.pumpAndSettle();
    expect(results.single!.map((e) => e.id), [3]);
  });

  testWidgets('tapping a row opens the picker with what was said, and the choice replaces it', (
    tester,
  ) async {
    final results = await _open(tester, _FakeSpeech());
    await tester.enterText(find.byType(TextField), '1 zzzz');
    await tester.pumpAndSettle();

    await tester.tap(find.text('No exercise found'));
    await tester.pumpAndSettle();
    // The picker's own search box is prefilled with the spoken words.
    expect(find.widgetWithText(TextField, 'zzzz'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'zzzz'), 'cable');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cable Row'));
    await tester.pumpAndSettle();

    expect(find.text('Add 1 exercise'), findsOneWidget);
    await tester.tap(find.text('Add 1 exercise'));
    await tester.pumpAndSettle();
    expect(results.single!.map((e) => e.id), [4]);
  });

  testWidgets('dictation fills the box as it is recognised and can be stopped', (tester) async {
    final speech = _FakeSpeech();
    await _open(tester, speech);

    await tester.tap(find.text('Tap and speak'));
    await tester.pump();
    expect(find.text('Stop listening'), findsOneWidget);
    expect(find.textContaining('Listening...'), findsOneWidget);

    speech.onText!('1 bench');
    await tester.pump();
    speech.onText!('1 bench press 2 reverse lunges');
    await tester.pump();
    expect(find.text('Add 2 exercises'), findsOneWidget);

    await tester.tap(find.text('Stop listening'));
    await tester.pumpAndSettle();
    expect(speech.stopped, isTrue);
    expect(find.text('Tap and speak'), findsOneWidget);
  });

  testWidgets('dictating again adds to the list instead of replacing it', (tester) async {
    final speech = _FakeSpeech();
    await _open(tester, speech);

    await tester.tap(find.text('Tap and speak'));
    await tester.pump();
    speech.onText!('1 bench press');
    await tester.pump();
    speech.onDone!();
    await tester.pump();

    await tester.tap(find.text('Tap and speak'));
    await tester.pump();
    speech.onText!('1 pull ups');
    await tester.pump();

    expect(find.text('Add 2 exercises'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Pull-up'), findsOneWidget);
  });

  testWidgets('says so when voice input is unavailable', (tester) async {
    await _open(tester, _FakeSpeech(error: 'Voice input is not available.'));

    await tester.tap(find.text('Tap and speak'));
    await tester.pumpAndSettle();

    expect(find.text('Voice input is not available.'), findsOneWidget);
    expect(find.text('Tap and speak'), findsOneWidget);
  });
}
