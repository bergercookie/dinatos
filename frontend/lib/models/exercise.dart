import 'equipment.dart';
import 'muscle_group.dart';

class Exercise {
  const Exercise({
    this.id,
    required this.name,
    this.tracksWeight = true,
    this.tracksReps = true,
    this.tracksDistance = false,
    this.tracksDuration = false,
    this.isCustom = true,
    this.equipment,
    this.primaryMuscles = const [],
    this.secondaryMuscles = const [],
  });

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
    id: json['id'] as int,
    name: json['name'] as String,
    tracksWeight: json['tracks_weight'] as bool,
    tracksReps: json['tracks_reps'] as bool,
    tracksDistance: json['tracks_distance'] as bool,
    tracksDuration: json['tracks_duration'] as bool,
    isCustom: json['is_custom'] as bool,
    equipment: json['equipment'] != null ? Equipment.fromJson(json['equipment'] as String) : null,
    primaryMuscles: (json['primary_muscles'] as List<dynamic>? ?? const [])
        .map((muscle) => MuscleGroup.fromJson(muscle as String))
        .toList(),
    secondaryMuscles: (json['secondary_muscles'] as List<dynamic>? ?? const [])
        .map((muscle) => MuscleGroup.fromJson(muscle as String))
        .toList(),
  );

  final int? id;
  final String name;
  final bool tracksWeight;
  final bool tracksReps;
  final bool tracksDistance;
  final bool tracksDuration;

  /// False only for the shipped, built-in catalog -- server-assigned, never
  /// editable/deletable (the backend rejects it with a 403). See
  /// `ExerciseFormScreen` and `ExerciseListScreen` for how the UI reflects
  /// this.
  final bool isCustom;

  final Equipment? equipment;

  /// A fixed, closed vocabulary (not free text) for what this exercise
  /// trains -- what the live workout screen's muscle-emphasis radar chart
  /// groups logged sets by. Secondary muscles count for half the volume a
  /// primary one does; see `features/activities/live/muscle_volume.dart`.
  final List<MuscleGroup> primaryMuscles;
  final List<MuscleGroup> secondaryMuscles;

  /// The subset of fields the create/update endpoints accept -- `id` and
  /// `isCustom` are both server-assigned, never sent back.
  Map<String, dynamic> toJson() => {
    'name': name,
    'tracks_weight': tracksWeight,
    'tracks_reps': tracksReps,
    'tracks_distance': tracksDistance,
    'tracks_duration': tracksDuration,
    'equipment': equipment?.toJson(),
    'primary_muscles': primaryMuscles.map((muscle) => muscle.toJson()).toList(),
    'secondary_muscles': secondaryMuscles.map((muscle) => muscle.toJson()).toList(),
  };
}
