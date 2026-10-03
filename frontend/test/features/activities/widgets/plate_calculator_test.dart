import 'package:dinatos_frontend/features/activities/widgets/plate_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A `Text` widget with exactly [data] -- unlike `find.text`, not a text field's contents.
Finder _label(String data) => find.byWidgetPredicate((w) => w is Text && w.data == data);

void main() {
  group('platesFor', () {
    test('loads the heaviest plates first', () {
      final load = platesFor(100)!;

      expect(load.perSide, [25, 15]);
      expect(load.loadedKg, 100);
      expect(load.isExact, isTrue);
    });

    test('an empty bar needs no plates', () {
      final load = platesFor(20)!;

      expect(load.perSide, isEmpty);
      expect(load.isExact, isTrue);
    });

    test('uses small plates without floating-point trouble', () {
      final load = platesFor(62.5)!;

      expect(load.perSide, [20, 1.25]);
      expect(load.loadedKg, 62.5);
      expect(load.isExact, isTrue);
    });

    test('a weight the plates cannot make is rounded down and reported short', () {
      final load = platesFor(61)!;

      expect(load.perSide, [20]);
      expect(load.loadedKg, 60);
      expect(load.shortKg, 1);
      expect(load.isExact, isFalse);
    });

    test('repeats a plate when one is not enough', () {
      expect(platesFor(220)!.perSide, [25, 25, 25, 25]);
    });

    test('honours a different bar and plate set', () {
      final load = platesFor(35, barKg: 15, plates: const [10, 5])!;

      expect(load.perSide, [10]);
      expect(load.loadedKg, 35);
    });

    test('is null below the bar', () => expect(platesFor(15), isNull));
  });

  test('describePlates', () {
    expect(describePlates([25, 2.5, 1.25]), '25 + 2.5 + 1.25');
    expect(describePlates([]), 'no plates');
  });

  group('dialog', () {
    Future<void> open(WidgetTester tester, {double? target}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPlateCalculator(context, targetKg: target),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('starts from the given weight', (tester) async {
      await open(tester, target: 82.5);

      expect(find.text('25 + 5 + 1.25'), findsOneWidget);
    });

    testWidgets('recalculates as the weight or the bar changes', (tester) async {
      await open(tester);
      expect(find.text('Enter the weight to load.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Weight to load (kg)'), '15');
      await tester.pump();
      expect(find.text('That is lighter than the bar.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Weight to load (kg)'), '60');
      await tester.pump();
      expect(_label('20'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Bar (kg)'), '10');
      await tester.pump();
      expect(_label('25'), findsOneWidget);
    });

    testWidgets('says so when the plates cannot make the weight exactly', (tester) async {
      await open(tester, target: 61);

      expect(find.textContaining('Closest with these plates: 60 kg (1 kg short)'), findsOneWidget);
    });

    testWidgets('closes', (tester) async {
      await open(tester, target: 60);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Plate calculator'), findsNothing);
    });
  });
}
