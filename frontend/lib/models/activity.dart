import 'set_type.dart';
import 'superset.dart';

/// See `models/routine.dart`'s `_unset` -- same reason: distinguishes "not
/// passed" from "explicitly cleared" in `copyWith`.
const _unset = Object();

class ActivitySet {
  const ActivitySet({
    this.id,
    this.uid = 0,
    this.position,
    this.setType = SetType.normal,
    this.weightKg,
    this.reps,
    this.distanceKm,
    this.durationSeconds,
    this.completed = true,
  });

  factory ActivitySet.fromJson(Map<String, dynamic> json) => ActivitySet(
    id: json['id'] as int,
    position: json['position'] as int,
    setType: SetType.fromJson(json['set_type'] as String),
    weightKg: (json['weight_kg'] as num?)?.toDouble(),
    reps: json['reps'] as int?,
    distanceKm: (json['distance_km'] as num?)?.toDouble(),
    durationSeconds: json['duration_seconds'] as int?,
    // Older servers have no such flag: everything they hold was done.
    completed: json['completed'] as bool? ?? true,
  );

  final int? id;

  /// See `uid.dart`; what a row is keyed on while this set is being edited.
  final int uid;
  final int? position;
  final SetType setType;
  final double? weightKg;
  final int? reps;
  final double? distanceKm;
  final int? durationSeconds;

  /// Ticked off as done. Only ticked sets count towards totals, records and
  /// statistics. Defaults to true -- a set logged after the fact was done --
  /// while the screens that add a set to a workout in progress create it
  /// unticked (`completed: false`).
  final bool completed;

  Map<String, dynamic> toJson() => {
    'set_type': setType.toJson(),
    'weight_kg': weightKg,
    'reps': reps,
    'distance_km': distanceKm,
    'duration_seconds': durationSeconds,
    'completed': completed,
  };

  ActivitySet copyWith({
    SetType? setType,
    Object? weightKg = _unset,
    Object? reps = _unset,
    Object? distanceKm = _unset,
    Object? durationSeconds = _unset,
    bool? completed,
  }) => ActivitySet(
    id: id,
    uid: uid,
    position: position,
    setType: setType ?? this.setType,
    weightKg: identical(weightKg, _unset) ? this.weightKg : weightKg as double?,
    reps: identical(reps, _unset) ? this.reps : reps as int?,
    distanceKm: identical(distanceKm, _unset) ? this.distanceKm : distanceKm as double?,
    durationSeconds: identical(durationSeconds, _unset)
        ? this.durationSeconds
        : durationSeconds as int?,
    completed: completed ?? this.completed,
  );
}

class ActivityExercise {
  const ActivityExercise({
    this.id,
    this.uid = 0,
    this.position,
    required this.exerciseId,
    this.supersetGroup,
    this.notes,
    this.sets = const [],
  });

  factory ActivityExercise.fromJson(Map<String, dynamic> json) => ActivityExercise(
    id: json['id'] as int,
    position: json['position'] as int,
    exerciseId: json['exercise_id'] as int,
    supersetGroup: json['superset_group'] as int?,
    notes: json['notes'] as String?,
    sets: (json['sets'] as List<dynamic>)
        .map((e) => ActivitySet.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final int? id;

  /// See `uid.dart`.
  final int uid;
  final int? position;
  final int exerciseId;

  /// Exercises sharing a group are done back-to-back as a superset; see
  /// `superset.dart` for how the groups are kept adjacent and numbered.
  final int? supersetGroup;
  final String? notes;
  final List<ActivitySet> sets;

  /// The sets that were actually done (ticked off); the rest are only planned.
  Iterable<ActivitySet> get completedSets => sets.where((s) => s.completed);

  Map<String, dynamic> toJson() => {
    'exercise_id': exerciseId,
    'superset_group': supersetGroup,
    'notes': notes,
    'sets': sets.map((s) => s.toJson()).toList(),
  };

  ActivityExercise copyWith({
    Object? supersetGroup = _unset,
    Object? notes = _unset,
    List<ActivitySet>? sets,
  }) => ActivityExercise(
    id: id,
    uid: uid,
    position: position,
    exerciseId: exerciseId,
    supersetGroup: identical(supersetGroup, _unset) ? this.supersetGroup : supersetGroup as int?,
    notes: identical(notes, _unset) ? this.notes : notes as String?,
    sets: sets ?? this.sets,
  );
}

/// How [normalizeSupersets] and friends read and write an exercise's group.
final activitySupersets = SupersetAccess<ActivityExercise>(
  groupOf: (e) => e.supersetGroup,
  withGroup: (e, group) => e.copyWith(supersetGroup: group),
);

class Activity {
  const Activity({
    this.id,
    required this.title,
    this.description,
    required this.startedAt,
    this.endedAt,
    this.routineId,
    this.exercises = const [],
  });

  factory Activity.fromJson(Map<String, dynamic> json) => Activity(
    id: json['id'] as int,
    title: json['title'] as String,
    description: json['description'] as String?,
    startedAt: DateTime.parse(json['started_at'] as String),
    endedAt: json['ended_at'] != null ? DateTime.parse(json['ended_at'] as String) : null,
    routineId: json['routine_id'] as int?,
    exercises: (json['exercises'] as List<dynamic>)
        .map((e) => ActivityExercise.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final int? id;
  final String title;
  final String? description;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? routineId;
  final List<ActivityExercise> exercises;

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'started_at': startedAt.toUtc().toIso8601String(),
    'ended_at': endedAt?.toUtc().toIso8601String(),
    'routine_id': routineId,
    'exercises': exercises.map((e) => e.toJson()).toList(),
  };

  Activity copyWith({
    String? title,
    String? description,
    DateTime? startedAt,
    DateTime? endedAt,
    int? routineId,
    List<ActivityExercise>? exercises,
  }) => Activity(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
    routineId: routineId ?? this.routineId,
    exercises: exercises ?? this.exercises,
  );
}
