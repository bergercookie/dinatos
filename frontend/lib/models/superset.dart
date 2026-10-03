/// Supersets: exercises done back-to-back, marked by sharing a `supersetGroup`.
///
/// A group is only meaningful as a run of *adjacent* exercises, so every edit
/// (linking, unlinking, moving, removing) goes through [normalizeSupersets],
/// which keeps the list in a canonical shape: each run of neighbours sharing a
/// group has at least two members, and runs are numbered 1, 2, ... in order.
/// That means a stale or hand-edited group number (a Hevy import, a restored
/// backup) is repaired the first time the list is edited, and the same code
/// serves both an activity's exercises and a routine's.
library;

/// Reads and writes the group of an item `T` (an `ActivityExercise` or a
/// `RoutineExercise`) without this file depending on either.
class SupersetAccess<T> {
  const SupersetAccess({required this.groupOf, required this.withGroup});

  final int? Function(T item) groupOf;
  final T Function(T item, int? group) withGroup;
}

/// Renumbers [items]' groups so each adjacent run of equal groups is a real
/// superset (two or more members) numbered 1, 2, ... in order; a lone member
/// or an ungrouped item gets no group.
List<T> normalizeSupersets<T>(List<T> items, SupersetAccess<T> access) {
  final result = <T>[];
  var next = 1;
  var i = 0;
  while (i < items.length) {
    final group = access.groupOf(items[i]);
    var end = i + 1;
    if (group != null) {
      while (end < items.length && access.groupOf(items[end]) == group) {
        end++;
      }
    }
    final isSuperset = group != null && end - i >= 2;
    final assigned = isSuperset ? next++ : null;
    for (var j = i; j < end; j++) {
      result.add(
        access.groupOf(items[j]) == assigned ? items[j] : access.withGroup(items[j], assigned),
      );
    }
    i = end;
  }
  return result;
}

/// Puts the item at [index] and the one after it into the same superset
/// (joining the existing one if either is already in one). A no-op on the
/// last item.
List<T> linkWithNext<T>(List<T> items, int index, SupersetAccess<T> access) {
  if (index < 0 || index + 1 >= items.length) return items;
  final here = access.groupOf(items[index]);
  final there = access.groupOf(items[index + 1]);
  // A number no existing group uses, so a fresh pair can't merge into one.
  final fresh =
      items.fold<int>(0, (m, e) => (access.groupOf(e) ?? 0) > m ? access.groupOf(e)! : m) + 1;
  final target = here ?? there ?? fresh;
  final updated = List<T>.of(items);
  updated[index] = access.withGroup(items[index], target);
  updated[index + 1] = access.withGroup(items[index + 1], target);
  // Joining two existing supersets: the whole second one comes along.
  if (there != null && there != target) {
    for (var i = index + 1; i < updated.length && access.groupOf(items[i]) == there; i++) {
      updated[i] = access.withGroup(updated[i], target);
    }
  }
  return normalizeSupersets(updated, access);
}

/// Takes the item at [index] out of its superset. If that splits the run, the
/// pieces left with a single member stop being supersets.
List<T> unlink<T>(List<T> items, int index, SupersetAccess<T> access) {
  if (index < 0 || index >= items.length || access.groupOf(items[index]) == null) return items;
  final updated = List<T>.of(items)..[index] = access.withGroup(items[index], null);
  return normalizeSupersets(updated, access);
}

/// Moves the item at [from] to [to] (both indexes into [items]).
List<T> moveItem<T>(List<T> items, int from, int to, SupersetAccess<T> access) {
  if (from < 0 || from >= items.length || to < 0 || to >= items.length || from == to) {
    return items;
  }
  final updated = List<T>.of(items);
  updated.insert(to, updated.removeAt(from));
  return normalizeSupersets(updated, access);
}

/// Drops the item at [index].
List<T> removeItem<T>(List<T> items, int index, SupersetAccess<T> access) {
  final updated = List<T>.of(items)..removeAt(index);
  return normalizeSupersets(updated, access);
}

/// "A", "B", ... for each group that appears in [groups], by first
/// appearance; null for an ungrouped position.
List<String?> supersetLabels(List<int?> groups) {
  final letters = <int, String>{};
  return [
    for (final group in groups)
      if (group == null)
        null
      else
        letters.putIfAbsent(group, () => String.fromCharCode(0x41 + letters.length % 26)),
  ];
}
