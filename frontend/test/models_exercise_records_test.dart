import 'package:dinatos_frontend/models/activity.dart';
import 'package:dinatos_frontend/models/exercise_history.dart';
import 'package:dinatos_frontend/models/exercise_records.dart';
import 'package:dinatos_frontend/models/set_type.dart';
import 'package:flutter_test/flutter_test.dart';

ActivitySet _set(double? kg, int? reps, {SetType type = SetType.normal}) =>
    ActivitySet(weightKg: kg, reps: reps, setType: type);

List<bool> _weight(List<SetRecord> flags) => flags.map((f) => f.weight).toList();
List<bool> _reps(List<SetRecord> flags) => flags.map((f) => f.reps).toList();

void main() {
  const prior = ExerciseRecords(maxWeightKg: 80, maxReps: 12);

  group('detectSetRecords', () {
    test('flags the first set past the best weight, and only again if it is beaten', () {
      final flags = detectSetRecords([
        _set(80, 5),
        _set(82.5, 5),
        _set(82.5, 5),
        _set(85, 3),
      ], prior);

      expect(_weight(flags), [false, true, false, true]);
    });

    test('a record needs a load: reps count only for a set with no weight', () {
      final flags = detectSetRecords([_set(60, 20), _set(null, 15), _set(null, 15)], prior);

      expect(_reps(flags), [false, true, false]);
      expect(_weight(flags), [false, false, false]);
    });

    test('warm-ups are never records', () {
      final flags = detectSetRecords([_set(100, 10, type: SetType.warmup), _set(81, 5)], prior);

      expect(_weight(flags), [false, true]);
    });

    test('an exercise with no history flags nothing by default', () {
      final flags = detectSetRecords([_set(60, 5), _set(70, 5)], const ExerciseRecords());

      expect(flags.any((f) => f.any), isFalse);
    });

    test('...but the first set counts when asked, as the end-of-workout summary does', () {
      final flags = detectSetRecords(
        [_set(60, 5), _set(70, 5)],
        const ExerciseRecords(),
        requirePrior: false,
      );

      expect(_weight(flags), [true, true]);
    });

    test('a set with nothing logged is never a record', () {
      expect(detectSetRecords([_set(null, null)], prior).single.any, isFalse);
    });
  });

  test('ExerciseRecords.isEmpty', () {
    expect(const ExerciseRecords().isEmpty, isTrue);
    expect(prior.isEmpty, isFalse);
  });

  test('ExerciseHistoryEntry reads the history endpoint\'s shape', () {
    final entry = ExerciseHistoryEntry.fromJson({
      'activity_id': 4,
      'activity_title': 'Push',
      'started_at': '2026-09-01T10:00:00Z',
      'sets': [
        {
          'set_type': 'warmup',
          'weight_kg': 40.0,
          'reps': 10,
          'distance_km': null,
          'duration_seconds': null,
          'rpe': 7.5,
        },
      ],
    });

    expect(entry.activityId, 4);
    expect(entry.startedAt, DateTime.utc(2026, 9, 1, 10));
    expect(entry.sets.single.setType, SetType.warmup);
    expect(entry.sets.single.rpe, 7.5);
  });
}
