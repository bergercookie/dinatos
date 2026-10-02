import 'package:dinatos_frontend/features/activities/live/elapsed_timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatElapsed', () {
    test('renders under an hour as mm:ss', () {
      expect(formatElapsed(const Duration(minutes: 5, seconds: 7)), '05:07');
    });

    test('renders an hour or more as h:mm:ss', () {
      expect(formatElapsed(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    });

    test('clamps a negative duration to zero instead of showing a minus sign', () {
      expect(formatElapsed(const Duration(seconds: -5)), '00:00');
    });
  });
}
