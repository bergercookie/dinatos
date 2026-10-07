import 'package:dinatos_frontend/features/exercises/exercise_text_matcher.dart';
import 'package:dinatos_frontend/models/exercise.dart';
import 'package:flutter_test/flutter_test.dart';

final _catalog = [
  const Exercise(id: 1, name: 'Bench Press'),
  const Exercise(id: 2, name: 'Incline Dumbbell Bench Press'),
  const Exercise(id: 3, name: 'Reverse Dumbbell Lunge'),
  const Exercise(id: 4, name: 'Pull-up'),
  const Exercise(id: 5, name: 'One-Arm Dumbbell Row'),
  const Exercise(id: 6, name: 'Squat'),
  const Exercise(id: 7, name: 'Barbell Squat'),
  const Exercise(id: 8, name: 'Romanian Deadlift'),
  const Exercise(id: 9, name: 'Dumbbell Curl'),
];

void main() {
  group('splitExerciseList', () {
    test('splits digits', () {
      expect(splitExerciseList('1 reverse lunges 2 bench press 3 pull ups'), [
        'reverse lunges',
        'bench press',
        'pull ups',
      ]);
    });

    test('splits number words, as a recogniser may write them', () {
      expect(splitExerciseList('One reverse lunges two bench press three pull ups'), [
        'reverse lunges',
        'bench press',
        'pull ups',
      ]);
    });

    test('splits on typed list markers and new lines', () {
      expect(splitExerciseList('1. Bench press\n2) Squat\n3: Curl'), [
        'Bench press',
        'Squat',
        'Curl',
      ]);
    });

    test('only the next expected number splits, so numbers in a name survive', () {
      expect(splitExerciseList('1 one arm dumbbell row 2 squat'), [
        'one arm dumbbell row',
        'squat',
      ]);
      expect(splitExerciseList('1 bench press 2 squat 21 curls'), [
        'bench press',
        'squat 21 curls',
      ]);
    });

    test('a second numbered run on a new line adds to the first', () {
      expect(splitExerciseList('1 squat 2 curl\n1 bench press 2 pull ups'), [
        'squat',
        'curl',
        'bench press',
        'pull ups',
      ]);
    });

    test('without numbers, splits on lines, commas and joining words', () {
      expect(splitExerciseList('bench press, squat and pull ups then curl'), [
        'bench press',
        'squat',
        'pull ups',
        'curl',
      ]);
      expect(splitExerciseList('bench press\nsquat'), ['bench press', 'squat']);
    });

    test('ignores blank input and a trailing joining word', () {
      expect(splitExerciseList('   '), isEmpty);
      expect(splitExerciseList('1 squat and 2 curl'), ['squat', 'curl']);
    });
  });

  group('ExerciseMatcher', () {
    final matcher = ExerciseMatcher(_catalog);

    test('an exact name, any case or word order, is exact', () {
      expect(matcher.match('bench press').exercise?.id, 1);
      expect(matcher.match('bench press').quality, MatchQuality.exact);
      expect(matcher.match('PRESS BENCH').exercise?.id, 1);
    });

    test('a partial name finds the full one (reverse lunges)', () {
      final match = matcher.match('reverse lunges');
      expect(match.exercise?.id, 3);
      expect(match.quality, MatchQuality.guess);
    });

    test('plurals and spacing differences are forgiven', () {
      expect(matcher.match('pull ups').exercise?.id, 4);
      expect(matcher.match('pull ups').quality, MatchQuality.exact);
      expect(matcher.match('pullups').exercise?.id, 4);
      expect(matcher.match('squats').exercise?.id, 6);
      expect(matcher.match('squats').quality, MatchQuality.exact);
    });

    test('abbreviations and a one-letter slip are forgiven', () {
      expect(matcher.match('db curl').exercise?.id, 9);
      expect(matcher.match('romanian deadlifts').exercise?.id, 8);
      expect(matcher.match('romanien deadlift').exercise?.id, 8);
    });

    test('the closest name wins over a longer one', () {
      expect(matcher.match('bench press').exercise?.id, 1);
      expect(matcher.match('dumbbell bench').exercise?.id, 2);
    });

    test('usage breaks a tie', () {
      final tie = [
        const Exercise(id: 10, name: 'Cable Row'),
        const Exercise(id: 11, name: 'Seated Row'),
      ];
      expect(ExerciseMatcher(tie).match('row').exercise?.id, 10);
      expect(ExerciseMatcher(tie, usage: {11: 5}).match('row').exercise?.id, 11);
    });

    test('only some words matching is weak, and offers the match as a suggestion', () {
      final match = matcher.match('dumbbell flyes');
      expect(match.quality, MatchQuality.weak);
      expect(match.exercise, isNotNull);
    });

    test('nothing alike is none', () {
      final match = matcher.match('zzzz');
      expect(match.quality, MatchQuality.none);
      expect(match.exercise, isNull);
      expect(matcher.match('').quality, MatchQuality.none);
    });

    test('lists other close candidates, best first', () {
      final match = matcher.match('squat');
      expect(match.exercise?.id, 6);
      expect(match.alternatives.map((e) => e.id), contains(7));
    });
  });
}
