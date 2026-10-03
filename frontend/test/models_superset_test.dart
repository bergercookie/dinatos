import 'package:dinatos_frontend/models/activity.dart';
import 'package:dinatos_frontend/models/superset.dart';
import 'package:flutter_test/flutter_test.dart';

final _access = SupersetAccess<ActivityExercise>(
  groupOf: (e) => e.supersetGroup,
  withGroup: (e, group) => e.copyWith(supersetGroup: group),
);

/// Exercises named by id, in the given groups (null = not in a superset).
List<ActivityExercise> _list(List<int?> groups) => [
  for (var i = 0; i < groups.length; i++) ActivityExercise(exerciseId: i, supersetGroup: groups[i]),
];

List<int?> _groups(List<ActivityExercise> items) => items.map((e) => e.supersetGroup).toList();
List<int> _order(List<ActivityExercise> items) => items.map((e) => e.exerciseId).toList();

void main() {
  group('normalizeSupersets', () {
    test('drops a group with a single member and renumbers the rest from 1', () {
      expect(_groups(normalizeSupersets(_list([7, null, 9, 9, null, 4]), _access)), [
        null,
        null,
        1,
        1,
        null,
        null,
      ]);
    });

    test('splits a group number reused by exercises that are not adjacent', () {
      expect(_groups(normalizeSupersets(_list([3, 3, null, 3, 3]), _access)), [1, 1, null, 2, 2]);
    });

    test('leaves an already canonical list as it was', () {
      final items = _list([1, 1, null, 2, 2, 2]);
      expect(normalizeSupersets(items, _access), orderedEquals(items));
    });
  });

  group('linkWithNext', () {
    test('pairs two loose exercises', () {
      expect(_groups(linkWithNext(_list([null, null, null]), 1, _access)), [null, 1, 1]);
    });

    test('joins the next exercise to an existing superset', () {
      expect(_groups(linkWithNext(_list([1, 1, null]), 1, _access)), [1, 1, 1]);
    });

    test('pulls the previous loose exercise into the next one\'s superset', () {
      expect(_groups(linkWithNext(_list([null, 1, 1]), 0, _access)), [1, 1, 1]);
    });

    test('merges two neighbouring supersets into one', () {
      expect(_groups(linkWithNext(_list([1, 1, 2, 2]), 1, _access)), [1, 1, 1, 1]);
    });

    test('does nothing on the last exercise or an out-of-range index', () {
      final items = _list([null, null]);
      expect(linkWithNext(items, 1, _access), same(items));
      expect(linkWithNext(items, -1, _access), same(items));
    });

    test('a new pair never merges into an existing superset elsewhere', () {
      expect(_groups(linkWithNext(_list([1, 1, null, null]), 2, _access)), [1, 1, 2, 2]);
    });
  });

  group('unlink', () {
    test('leaving a pair breaks the whole superset up', () {
      expect(_groups(unlink(_list([1, 1, null]), 0, _access)), [null, null, null]);
    });

    test('leaving a trio from its end keeps the other two together', () {
      expect(_groups(unlink(_list([1, 1, 1]), 2, _access)), [1, 1, null]);
    });

    test('leaving a trio from the middle leaves two singles, so no superset', () {
      expect(_groups(unlink(_list([1, 1, 1]), 1, _access)), [null, null, null]);
    });

    test('an exercise in no superset is a no-op', () {
      final items = _list([null, 1, 1]);
      expect(unlink(items, 0, _access), same(items));
    });
  });

  group('moveItem', () {
    test('reorders and keeps a superset that moved together', () {
      final moved = moveItem(_list([null, 1, 1]), 0, 2, _access);
      expect(_order(moved), [1, 2, 0]);
      expect(_groups(moved), [1, 1, null]);
    });

    test('moving a member out of its superset dissolves it', () {
      final moved = moveItem(_list([1, 1, null]), 1, 2, _access);
      expect(_order(moved), [0, 2, 1]);
      expect(_groups(moved), [null, null, null]);
    });

    test('an out-of-range or no-op move changes nothing', () {
      final items = _list([null, null]);
      expect(moveItem(items, 0, 0, _access), same(items));
      expect(moveItem(items, 0, 5, _access), same(items));
      expect(moveItem(items, -1, 0, _access), same(items));
    });
  });

  test('removeItem drops a superset left with one member', () {
    final removed = removeItem(_list([1, 1, null]), 0, _access);
    expect(_order(removed), [1, 2]);
    expect(_groups(removed), [null, null]);
  });

  test('supersetLabels letters groups by first appearance', () {
    expect(supersetLabels([null, 5, 5, null, 2, 2, 5]), [null, 'A', 'A', null, 'B', 'B', 'A']);
  });
}
