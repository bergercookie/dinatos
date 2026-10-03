import 'package:dinatos_frontend/core/theme_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to following the system', () async {
    expect(await const ThemeModeStorage().read(), ThemeMode.system);
  });

  test('round-trips every mode', () async {
    for (final mode in ThemeMode.values) {
      await const ThemeModeStorage().write(mode);
      expect(await const ThemeModeStorage().read(), mode);
    }
  });

  test('an unrecognised stored value falls back to system', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'sepia'});
    expect(await const ThemeModeStorage().read(), ThemeMode.system);
  });
}
