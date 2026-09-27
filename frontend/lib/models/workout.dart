import 'set_type.dart';

/// Distinguishes "not passed" from "explicitly passed null" in `copyWith`,
/// so clearing a field (e.g. a set's weight back to empty) actually clears
/// it instead of `?? this.field` silently keeping the old value.
const _unset = Object();

class WorkoutSet {
  const WorkoutSet({
    this.id,
    this.position,
    this.setType = SetType.normal,
    this.targetWeightKg,
    this.targetReps,
    this.targetDistanceKm,
    this.targetDurationSeconds,
  });

  factory WorkoutSet.fromJson(Map<String, dynamic> json) => WorkoutSet(
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

  WorkoutSet copyWith({
    SetType? setType,
    Object? targetWeightKg = _unset,
    Object? targetReps = _unset,
    Object? targetDistanceKm = _unset,
    Object? targetDurationSeconds = _unset,
  }) => WorkoutSet(
    id: id,
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

class WorkoutExercise {
  const WorkoutExercise({
    this.id,
    this.position,
    required this.exerciseId,
    this.notes,
    this.sets = const [],
  });

  factory WorkoutExercise.fromJson(Map<String, dynamic> json) => WorkoutExercise(
    id: json['id'] as int,
    position: json['position'] as int,
    exerciseId: json['exercise_id'] as int,
    notes: json['notes'] as String?,
    sets: (json['sets'] as List<dynamic>)
        .map((e) => WorkoutSet.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final int? id;
  final int? position;
  final int exerciseId;
  final String? notes;
  final List<WorkoutSet> sets;

  Map<String, dynamic> toJson() => {
    'exercise_id': exerciseId,
    'notes': notes,
    'sets': sets.map((s) => s.toJson()).toList(),
  };

  WorkoutExercise copyWith({String? notes, List<WorkoutSet>? sets}) => WorkoutExercise(
    id: id,
    position: position,
    exerciseId: exerciseId,
    notes: notes ?? this.notes,
    sets: sets ?? this.sets,
  );
}

class Workout {
  const Workout({this.id, required this.name, this.description, this.exercises = const []});

  factory Workout.fromJson(Map<String, dynamic> json) => Workout(
    id: json['id'] as int,
    name: json['name'] as String,
    description: json['description'] as String?,
    exercises: (json['exercises'] as List<dynamic>)
        .map((e) => WorkoutExercise.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final int? id;
  final String name;
  final String? description;
  final List<WorkoutExercise> exercises;

  /// The `POST`/`PUT` body -- a full replace, matching the backend's "no
  /// endpoint for patching one set in isolation" design.
  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'exercises': exercises.map((e) => e.toJson()).toList(),
  };

  Workout copyWith({String? name, String? description, List<WorkoutExercise>? exercises}) =>
      Workout(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        exercises: exercises ?? this.exercises,
      );
}
