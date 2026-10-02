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

  group('parseElapsed', () {
    test('accepts m:ss, h:mm:ss and bare minutes', () {
      expect(parseElapsed('12:30'), const Duration(minutes: 12, seconds: 30));
      expect(parseElapsed('1:02:03'), const Duration(hours: 1, minutes: 2, seconds: 3));
      expect(parseElapsed(' 45 '), const Duration(minutes: 45));
    });

    test('rejects junk, negatives and out-of-range parts', () {
      for (final bad in ['', 'abc', '-5', '1:75', '1:2:3:4', '1::3']) {
        expect(parseElapsed(bad), isNull, reason: bad);
      }
    });
  });
}
