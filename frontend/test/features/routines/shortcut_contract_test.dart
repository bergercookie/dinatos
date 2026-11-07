import 'dart:io';

import 'package:dinatos_frontend/features/routines/routine_shortcuts.dart';
import 'package:flutter_test/flutter_test.dart';

/// `MainActivity.kt` cannot be compiled or run under `flutter test`, and the
/// Dart and Kotlin halves of the routine shortcut only meet through plain
/// strings: the channel, its three methods and the launch intent's action and
/// extra. A rename on one side alone would leave a shortcut that pins fine and
/// then does nothing, so this checks the Kotlin source still spells out every
/// string the Dart side uses (and the manifest still allows the intent).
void main() {
  final kotlin = File(
    'android/app/src/main/kotlin/dev/bergercookie/dinatos_frontend/MainActivity.kt',
  ).readAsStringSync();
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('MainActivity uses the same channel, methods and intent names as Dart', () {
    for (final literal in [
      routineShortcutsChannelName,
      pinShortcutMethod,
      initialRoutineIdMethod,
      routineLaunchedMethod,
      startRoutineIntentAction,
      routineIdIntentExtra,
    ]) {
      expect(kotlin, contains('"$literal"'), reason: 'MainActivity.kt lost "$literal"');
    }
  });

  test('MainActivity pins with ShortcutManager and a stable per-routine id', () {
    expect(kotlin, contains('requestPinShortcut'));
    expect(kotlin, contains('"routine-\$routineId"'));
  });

  test('MainActivity handles a shortcut tapped while the app is running', () {
    expect(kotlin, contains('override fun onNewIntent'));
    expect(kotlin, contains('METHOD_ROUTINE_LAUNCHED'));
  });

  test('the main activity stays singleTop and exported, so a shortcut reaches onNewIntent', () {
    expect(manifest, contains('android:launchMode="singleTop"'));
    expect(manifest, contains('android:exported="true"'));
  });

  test('the channel name matches the app id', () {
    expect(routineShortcutsChannelName, startsWith('dev.bergercookie.dinatos'));
    expect(startRoutineIntentAction, startsWith('dev.bergercookie.dinatos'));
  });
}
