import 'package:dinatos_frontend/core/app_info.dart';
import 'package:dinatos_frontend/core/external_link.dart';
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

    expect(find.text('UI version'), findsOneWidget);
    expect(find.text(githubUrl), findsOneWidget);

    await tester.tap(find.text('GitHub project'));
    await tester.pump();

    expect(opened, [Uri.parse('https://github.com/bergercookie/dinatos')]);
  });
}
