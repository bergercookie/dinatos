import 'set_type.dart';
import 'superset.dart';

/// Distinguishes "not passed" from "explicitly passed null" in `copyWith`,
/// so clearing a field (e.g. a set's weight back to empty) actually clears
/// it instead of `?? this.field` silently keeping the old value.
const _unset = Object();

class RoutineSet {
  const RoutineSet({
    this.id,
    this.uid = 0,
    this.position,
    this.setType = SetType.normal,
    this.targetWeightKg,
    this.targetReps,
    this.targetDistanceKm,
    this.targetDurationSeconds,
  });

  factory RoutineSet.fromJson(Map<String, dynamic> json) => RoutineSet(
    id: json['id'] as int,
    position: json['position'] as int,
    setType: SetType.fromJson(json['set_type'] as String),
    targetWeightKg: (json['target_weight_kg'] as num?)?.toDouble(),
    targetReps: json['target_reps'] as int?,
    targetDistanceKm: (json['target_distance_km'] as num?)?.toDouble(),
    targetDurationSeconds: json['target_duration_seconds'] as int?,
  );

  /// Present on a set read back from the API; absent on one still being
  /// composed client-side before its first `POST`/`PUT`.
  final int? id;

  /// See `uid.dart`.
  final int uid;
  final int? position;
  final SetType setType;
  final double? targetWeightKg;
  final int? targetReps;
  final double? targetDistanceKm;
  final int? targetDurationSeconds;

  Map<String, dynamic> toJson() => {
    'set_type': setType.toJson(),
    'target_weight_kg': targetWeightKg,
    'target_reps': targetReps,
    'target_distance_km': targetDistanceKm,
    'target_duration_seconds': targetDurationSeconds,
  };

  RoutineSet copyWith({
    SetType? setType,
    Object? targetWeightKg = _unset,
    Object? targetReps = _unset,
    Object? targetDistanceKm = _unset,
    Object? targetDurationSeconds = _unset,
  }) => RoutineSet(
    id: id,
    uid: uid,
    position: position,
    setType: setType ?? this.setType,
    targetWeightKg: identical(targetWeightKg, _unset)
        ? this.targetWeightKg
        : targetWeightKg as double?,
    targetReps: identical(targetReps, _unset) ? this.targetReps : targetReps as int?,
    targetDistanceKm: identical(targetDistanceKm, _unset)
        ? this.targetDistanceKm
        : targetDistanceKm as double?,
    targetDurationSeconds: identical(targetDurationSeconds, _unset)
        ? this.targetDurationSeconds
        : targetDurationSeconds as int?,
  );
}

class RoutineExercise {
  const RoutineExercise({
    this.id,
    this.uid = 0,
    this.position,
    required this.exerciseId,
    this.supersetGroup,
    this.notes,
    this.sets = const [],
  });

  factory RoutineExercise.fromJson(Map<String, dynamic> json) => RoutineExercise(
    id: json['id'] as int,
    position: json['position'] as int,
    exerciseId: json['exercise_id'] as int,
    supersetGroup: json['superset_group'] as int?,
    notes: json['notes'] as String?,
    sets: (json['sets'] as List<dynamic>)
        .map((e) => RoutineSet.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final int? id;

  /// See `uid.dart`.
  final int uid;
  final int? position;
  final int exerciseId;

  /// Exercises sharing a group are done back-to-back as a superset; see
  /// `superset.dart`.
  final int? supersetGroup;
  final String? notes;
  final List<RoutineSet> sets;

  Map<String, dynamic> toJson() => {
    'exercise_id': exerciseId,
    'superset_group': supersetGroup,
    'notes': notes,
    'sets': sets.map((s) => s.toJson()).toList(),
  };

  RoutineExercise copyWith({
    Object? supersetGroup = _unset,
    Object? notes = _unset,
    List<RoutineSet>? sets,
  }) => RoutineExercise(
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
final routineSupersets = SupersetAccess<RoutineExercise>(
  groupOf: (e) => e.supersetGroup,
  withGroup: (e, group) => e.copyWith(supersetGroup: group),
);

class Routine {
  const Routine({this.id, required this.name, this.description, this.exercises = const []});

  factory Routine.fromJson(Map<String, dynamic> json) => Routine(
    id: json['id'] as int,
    name: json['name'] as String,
    description: json['description'] as String?,
    exercises: (json['exercises'] as List<dynamic>)
        .map((e) => RoutineExercise.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final int? id;
  final String name;
  final String? description;
  final List<RoutineExercise> exercises;

  /// The `POST`/`PUT` body -- a full replace, matching the backend's "no
  /// endpoint for patching one set in isolation" design.
  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'exercises': exercises.map((e) => e.toJson()).toList(),
  };

  Routine copyWith({String? name, String? description, List<RoutineExercise>? exercises}) =>
      Routine(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        exercises: exercises ?? this.exercises,
      );
}
