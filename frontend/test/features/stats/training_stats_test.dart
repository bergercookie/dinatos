import 'package:dinatos_frontend/features/stats/training_stats.dart';
import 'package:dinatos_frontend/models/activity.dart';
import 'package:dinatos_frontend/models/exercise.dart';
import 'package:dinatos_frontend/models/muscle_group.dart';
import 'package:dinatos_frontend/models/set_type.dart';
import 'package:flutter_test/flutter_test.dart';

// A Wednesday.
final _now = DateTime(2026, 9, 30, 12);

const _bench = Exercise(
  id: 1,
  name: 'Bench Press',
  primaryMuscles: [MuscleGroup.chest],
  secondaryMuscles: [MuscleGroup.triceps],
);
const _squat = Exercise(id: 2, name: 'Squat', primaryMuscles: [MuscleGroup.quadriceps]);

ActivitySet _set(double? kg, int? reps, {SetType type = SetType.normal}) =>
    ActivitySet(weightKg: kg, reps: reps, setType: type);

Activity _activity(DateTime start, {int? minutes, List<ActivityExercise> exercises = const []}) =>
    Activity(
      title: 't',
      startedAt: start,
      endedAt: minutes == null ? null : start.add(Duration(minutes: minutes)),
      exercises: exercises,
    );

void main() {
  test('empty history yields zeros and no duration', () {
    final stats = TrainingStats.compute(const [], now: _now);
    expect(stats.workouts, 0);
    expect(stats.workoutsPerWeek, 0);
    expect(stats.averageDuration, isNull);
    expect(stats.longestDayStreak, 0);
    expect(stats.weeklyCounts, everyElement(0));
    expect(stats.weeklyCounts, hasLength(statsWeeklyChartWeeks));
  });

  test('average duration only counts workouts that have an end time', () {
    final stats = TrainingStats.compute([
      _activity(DateTime(2026, 9, 28, 10), minutes: 60),
      _activity(DateTime(2026, 9, 29, 10), minutes: 30),
      _activity(DateTime(2026, 9, 30, 9)),
    ], now: _now);
    expect(stats.workouts, 3);
    expect(stats.timedWorkouts, 2);
    expect(stats.averageDuration, const Duration(minutes: 45));
    expect(stats.longestDuration, const Duration(minutes: 60));
  });

  test('range filters workouts; per-week chart ignores it', () {
    final old = _activity(DateTime(2026, 8, 1, 10)); // 60 days ago
    final recent = _activity(DateTime(2026, 9, 29, 10));
    final month = TrainingStats.compute([old, recent], range: StatsRange.month, now: _now);
    expect(month.workouts, 1);
    expect(month.weeklyCounts.reduce((a, b) => a + b), 2);
    expect(TrainingStats.compute([old, recent], now: _now).workouts, 2);
  });

  test('workouts per week averages over the span since the first workout', () {
    // First workout 14 days before "today" => 15 days => 15/7 weeks.
    final stats = TrainingStats.compute([
      _activity(DateTime(2026, 9, 16, 10)),
      _activity(DateTime(2026, 9, 23, 10)),
      _activity(DateTime(2026, 9, 30, 10)),
    ], now: _now);
    expect(stats.workoutsPerWeek, closeTo(3 / (15 / 7), 1e-9));
  });

  test('weekday and weekly buckets', () {
    final stats = TrainingStats.compute([
      _activity(DateTime(2026, 9, 28, 10)), // Monday, this week
      _activity(DateTime(2026, 9, 30, 10)), // Wednesday, this week
      _activity(DateTime(2026, 9, 23, 10)), // Wednesday, last week
    ], now: _now);
    expect(stats.weekdayCounts, [1, 0, 2, 0, 0, 0, 0]);
    expect(stats.weeklyCounts.last, 2);
    expect(stats.weeklyCounts[statsWeeklyChartWeeks - 2], 1);
    expect(stats.weekStarts.last, DateTime(2026, 9, 28));
  });

  test('muscle sets: secondary counts half, warm-ups are skipped', () {
    final stats = TrainingStats.compute(
      [
        _activity(
          DateTime(2026, 9, 30, 10),
          exercises: [
            ActivityExercise(
              exerciseId: 1,
              sets: [
                _set(60, 10, type: SetType.warmup),
                _set(100, 5),
                _set(100, 5),
              ],
            ),
          ],
        ),
      ],
      catalog: const [_bench],
      now: _now,
    );
    expect(stats.muscleSets[MuscleGroup.chest], 2);
    expect(stats.muscleSets[MuscleGroup.triceps], 1);
    expect(stats.totalSets, 3);
    expect(stats.totalVolumeKg, 1000);
  });

  test('top exercises rank by sessions, then sets; unknown ids still listed', () {
    ActivityExercise ex(int id, int sets) =>
        ActivityExercise(exerciseId: id, sets: [for (var i = 0; i < sets; i++) _set(50, 5)]);
    final stats = TrainingStats.compute(
      [
        _activity(DateTime(2026, 9, 28, 10), exercises: [ex(1, 3), ex(2, 1), ex(99, 1)]),
        _activity(DateTime(2026, 9, 29, 10), exercises: [ex(1, 3), ex(2, 4)]),
        _activity(DateTime(2026, 9, 30, 10), exercises: [ex(2, 1)]),
      ],
      catalog: const [_bench, _squat],
      now: _now,
    );
    expect(stats.topExercises.map((e) => e.name), ['Squat', 'Bench Press', 'Exercise #99']);
    expect(stats.topExercises.first.sessions, 3);
    expect(stats.topExercises.first.sets, 6);
  });

  test('top lifts use the best estimated 1RM per exercise', () {
    final stats = TrainingStats.compute(
      [
        _activity(
          DateTime(2026, 9, 30, 10),
          exercises: [
            ActivityExercise(
              exerciseId: 1,
              sets: [
                _set(100, 5),
                _set(110, 1),
                _set(150, 10, type: SetType.warmup),
              ],
            ),
            ActivityExercise(exerciseId: 2, sets: [_set(140, 8)]),
          ],
        ),
      ],
      catalog: const [_bench, _squat],
      now: _now,
    );
    expect(stats.topLifts.map((l) => l.name), ['Squat', 'Bench Press']);
    // 100 x 5 (~116.7) beats 110 x 1; the 150 x 10 warm-up is ignored.
    expect(stats.topLifts.last.weightKg, 100);
    expect(stats.topLifts.last.reps, 5);
  });

  test('estimateOneRepMax', () {
    expect(estimateOneRepMax(100, 1), 100);
    expect(estimateOneRepMax(100, 5), closeTo(116.667, 0.001));
  });

  test('longest day streak', () {
    final stats = TrainingStats.compute([
      _activity(DateTime(2026, 9, 1, 10)),
      _activity(DateTime(2026, 9, 2, 10)),
      _activity(DateTime(2026, 9, 3, 10)),
      _activity(DateTime(2026, 9, 3, 18)),
      _activity(DateTime(2026, 9, 10, 10)),
      _activity(DateTime(2026, 9, 11, 10)),
    ], now: _now);
    expect(stats.longestDayStreak, 3);
  });

  test('formatters', () {
    expect(formatDuration(const Duration(minutes: 45)), '45 min');
    expect(formatDuration(const Duration(minutes: 65)), '1h 05m');
    expect(formatWeight(820), '820 kg');
    expect(formatWeight(12400), '12.4 t');
  });
}
