import 'package:dinatos_frontend/core/widgets/responsive_body.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget body) => MaterialApp(home: Scaffold(body: body));

Future<void> _wheel(WidgetTester tester, Offset at, double dy) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(at));
  await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
  await tester.pump();
}

void main() {
  late ScrollController controller;

  setUp(() {
    controller = ScrollController();
    addTearDown(controller.dispose);
  });

  Widget list() => ResponsiveBody(
    child: ListView(
      controller: controller,
      children: [for (var i = 0; i < 100; i++) SizedBox(height: 50, child: Text('row $i'))],
    ),
  );

  testWidgets('the wheel scrolls the list from the empty margin beside it', (tester) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(list()));

    // Far left of the 1600px window; the column is only 640px wide, centered.
    await _wheel(tester, const Offset(40, 400), 200);
    expect(controller.offset, 200);
    await _wheel(tester, const Offset(1560, 400), 100);
    expect(controller.offset, 300);
  });

  testWidgets('over the column it scrolls once, not twice', (tester) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(list()));

    await _wheel(tester, const Offset(800, 400), 200);
    expect(controller.offset, 200);
  });

  testWidgets('the content stays capped at its maximum width', (tester) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(list()));

    expect(tester.getSize(find.byType(ListView)).width, 640);
  });

  testWidgets('a body with nothing to scroll ignores the wheel', (tester) async {
    await tester.pumpWidget(_app(const ResponsiveBody(child: Text('static'))));
    await _wheel(tester, const Offset(5, 5), 100);
    expect(find.text('static'), findsOneWidget);
  });
}
