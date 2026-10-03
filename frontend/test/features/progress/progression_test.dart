import 'package:dinatos_frontend/features/progress/progression.dart';
import 'package:dinatos_frontend/models/activity.dart';
import 'package:dinatos_frontend/models/exercise_history.dart';
import 'package:dinatos_frontend/models/set_type.dart';
import 'package:flutter_test/flutter_test.dart';

ActivitySet _set(double? kg, int? reps, {SetType type = SetType.normal, double? rpe}) =>
    ActivitySet(weightKg: kg, reps: reps, setType: type, rpe: rpe);

ExerciseHistoryEntry _entry(List<ActivitySet> sets, {int day = 1, int id = 1}) =>
    ExerciseHistoryEntry(
      activityId: id,
      activityTitle: 'Session $id',
      startedAt: DateTime.utc(2026, 1, day),
      sets: sets,
    );

/// Newest-first history of one top set per session, [weights] oldest first.
List<ExerciseHistoryEntry> _history(List<double> weights, {int reps = 5}) => [
  for (var i = weights.length - 1; i >= 0; i--)
    _entry([_set(weights[i], reps)], day: i + 1, id: i + 1),
];

void main() {
  group('estimateOneRepMax', () {
    test('is the weight itself for a single', () => expect(estimateOneRepMax(100, 1), 100));

    test('follows Epley for several reps', () {
      expect(estimateOneRepMax(60, 10), closeTo(80, 1e-9));
    });

    test('is null without a load, without reps, or past the reliable rep range', () {
      expect(estimateOneRepMax(null, 5), isNull);
      expect(estimateOneRepMax(0, 5), isNull);
      expect(estimateOneRepMax(50, null), isNull);
      expect(estimateOneRepMax(50, 0), isNull);
      expect(estimateOneRepMax(20, maxRepsForEstimate + 1), isNull);
    });
  });

  group('summarizeSession', () {
    test('reads top set, volume, reps and estimated 1RM from working sets only', () {
      final stats = summarizeSession(
        _entry([_set(40, 10, type: SetType.warmup), _set(80, 5), _set(80, 6), _set(70, 8)]),
      );

      expect(stats.workingSets, 3);
      expect(stats.volumeKg, 80 * 5 + 80 * 6 + 70 * 8);
      expect(stats.topWeightKg, 80);
      expect(stats.topWeightReps, 6); // the tie goes to more reps
      expect(stats.bestReps, 8);
      expect(stats.bestOneRepMaxKg, closeTo(80 * (1 + 6 / 30), 1e-9));
      expect(stats.performance, stats.bestOneRepMaxKg);
    });

    test('a body-weight session is judged by its best reps', () {
      final stats = summarizeSession(_entry([_set(null, 12), _set(null, 9)]));

      expect(stats.topWeightKg, isNull);
      expect(stats.volumeKg, 0);
      expect(stats.bestOneRepMaxKg, isNull);
      expect(stats.performance, 12);
    });

    test('a session of nothing measurable has no performance', () {
      expect(summarizeSession(_entry([_set(null, null)])).performance, isNull);
    });
  });

  test('sessionTimeline is oldest first and skips warm-up-only sessions', () {
    final timeline = sessionTimeline([
      _entry([_set(50, 5)], day: 3),
      _entry([_set(40, 10, type: SetType.warmup)], day: 2),
      _entry([_set(45, 5)], day: 1),
    ]);

    expect(timeline.map((s) => s.topWeightKg), [45, 50]);
  });

  group('describeSets', () {
    test('collapses identical sets', () {
      expect(describeSets([_set(60, 8), _set(60, 8), _set(60, 8)]), '3 × 8 @ 60 kg');
    });

    test('lists the reps when they differ at one weight', () {
      expect(describeSets([_set(60, 8), _set(60, 6)]), '8, 6 reps @ 60 kg');
    });

    test('lists weight × reps when the weight differs', () {
      expect(describeSets([_set(60, 8), _set(62.5, 6)]), '60×8, 62.5×6');
    });

    test('drops the weight for a body-weight set and ignores warm-ups', () {
      expect(
        describeSets([_set(null, 10), _set(null, 10), _set(20, 5, type: SetType.warmup)]),
        '2 × 10',
      );
      expect(describeSets([_set(20, 5, type: SetType.warmup)]), '');
    });
  });

  group('suggestOverload', () {
    test('adds weight once every set at the top weight hit the same reps', () {
      final suggestion = suggestOverload(_entry([_set(60, 8), _set(60, 8), _set(60, 8)]))!;

      expect(suggestion.kind, SuggestionKind.increaseWeight);
      expect(suggestion.weightKg, 62.5);
      expect(suggestion.reps, 8);
      expect(suggestion.setCount, 3);
      expect(suggestion.message, 'Last time 3 × 8 @ 60 kg. Try 62.5 kg × 8.');
    });

    test('keeps the weight and aims for the best reps when a set fell short', () {
      final suggestion = suggestOverload(_entry([_set(60, 8), _set(60, 8), _set(60, 6)]))!;

      expect(suggestion.kind, SuggestionKind.repeatWeight);
      expect(suggestion.weightKg, 60);
      expect(suggestion.reps, 8);
      expect(suggestion.message, contains('aim for 8 on every set'));
    });

    test('repeats a load that was logged as near-maximal effort', () {
      final suggestion = suggestOverload(_entry([_set(100, 5, rpe: 9.5), _set(100, 5, rpe: 10)]))!;

      expect(suggestion.kind, SuggestionKind.repeatWeight);
      expect(suggestion.weightKg, 100);
      expect(suggestion.message, contains('RPE 9.75'));
    });

    test('steps by 1 kg under 20 kg', () {
      expect(suggestOverload(_entry([_set(12, 10), _set(12, 10)]))!.weightKg, 13);
    });

    test('builds on the heaviest weight, ignoring lighter back-off sets', () {
      final suggestion = suggestOverload(_entry([_set(80, 5), _set(80, 5), _set(60, 10)]))!;

      expect(suggestion.weightKg, 82.5);
      expect(suggestion.reps, 5);
    });

    test('ignores warm-ups, and drop or failure sets when there are normal ones', () {
      final suggestion = suggestOverload(
        _entry([
          _set(40, 10, type: SetType.warmup),
          _set(60, 8),
          _set(60, 8),
          _set(80, 3, type: SetType.failure),
          _set(40, 15, type: SetType.dropset),
        ]),
      )!;

      expect(suggestion.weightKg, 62.5);
      expect(suggestion.setCount, 2);
    });

    test('falls back to non-normal working sets when that is all there was', () {
      final suggestion = suggestOverload(_entry([_set(50, 8, type: SetType.failure)]))!;
      expect(suggestion.weightKg, 52.5);
    });

    test('a body-weight exercise just adds a rep', () {
      final suggestion = suggestOverload(_entry([_set(null, 10), _set(null, 8)]))!;

      expect(suggestion.kind, SuggestionKind.addRep);
      expect(suggestion.weightKg, isNull);
      expect(suggestion.reps, 11);
    });

    test('is null with no history or nothing usable in it', () {
      expect(suggestOverload(null), isNull);
      expect(suggestOverload(_entry([_set(40, 10, type: SetType.warmup), _set(60, null)])), isNull);
    });
  });

  group('applySuggestion', () {
    final suggestion = suggestOverload(_entry([_set(60, 8), _set(60, 8), _set(60, 8)]))!;

    test('fills only the empty values of existing working sets', () {
      final applied = applySuggestion(
        [_set(20, 10, type: SetType.warmup), _set(null, null), _set(65, null), _set(null, 5)],
        suggestion,
        newSet: () => const ActivitySet(),
      );

      expect(applied.map((s) => s.weightKg), [20, 62.5, 65, 62.5]);
      expect(applied.map((s) => s.reps), [10, 8, 8, 5]);
    });

    test('creates as many sets as last time when there are none', () {
      final applied = applySuggestion([], suggestion, newSet: () => const ActivitySet());

      expect(applied, hasLength(3));
      expect(applied.every((s) => s.weightKg == 62.5 && s.reps == 8), isTrue);
    });
  });

  group('detectPlateau', () {
    test('is null while there is little history', () {
      expect(detectPlateau(_history([60, 60, 60, 60])), isNull);
    });

    test('is null while the lift is still improving', () {
      expect(detectPlateau(_history([60, 62.5, 65, 67.5, 70, 72.5])), isNull);
    });

    test('is found once the best is several sessions behind', () {
      final plateau = detectPlateau(_history([60, 62.5, 65, 65, 62.5, 65, 62.5]))!;

      expect(plateau.sessionsSinceBest, 4);
      expect(plateau.bestDate, DateTime.utc(2026, 1, 3)); // the earliest 65, not a repeat of it
      expect(plateau.isOneRepMax, isTrue);
      expect(plateau.best, closeTo(65 * (1 + 5 / 30), 1e-9));
    });

    test('a new best resets it', () {
      expect(detectPlateau(_history([60, 62.5, 62.5, 62.5, 62.5, 70])), isNull);
    });

    test('a gain of under half a percent is not progress', () {
      expect(detectPlateau(_history([100, 100.2, 100, 100, 100, 100])), isNotNull);
    });

    test('works on reps for a body-weight exercise', () {
      final history = [
        for (final (i, reps) in [8, 10, 10, 9, 9, 8].indexed.toList().reversed)
          _entry([_set(null, reps)], day: i + 1, id: i + 1),
      ];

      final plateau = detectPlateau(history)!;
      expect(plateau.isOneRepMax, isFalse);
      expect(plateau.best, 10);
    });
  });
}
