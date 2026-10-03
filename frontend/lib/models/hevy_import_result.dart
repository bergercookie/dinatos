import 'equipment.dart';
import 'muscle_group.dart';

/// A custom exercise a Hevy import had to create because no catalog
/// exercise matched it exactly, with the equipment/muscles the backend
/// *guessed* for it (already saved on the exercise). The flags say which
/// fields are guesses, so the UI can ask for a review.
class ImportedExercise {
  const ImportedExercise({
    required this.id,
    required this.name,
    this.equipment,
    this.primaryMuscles = const [],
    this.secondaryMuscles = const [],
    this.equipmentGuessed = false,
    this.musclesGuessed = false,
  });

  factory ImportedExercise.fromJson(Map<String, dynamic> json) => ImportedExercise(
    id: json['id'] as int,
    name: json['name'] as String,
    equipment: json['equipment'] != null ? Equipment.fromJson(json['equipment'] as String) : null,
    primaryMuscles: _muscles(json['primary_muscles']),
    secondaryMuscles: _muscles(json['secondary_muscles']),
    equipmentGuessed: json['equipment_guessed'] as bool? ?? false,
    musclesGuessed: json['muscles_guessed'] as bool? ?? false,
  );

  static List<MuscleGroup> _muscles(Object? raw) => (raw as List<dynamic>? ?? const [])
      .map((muscle) => MuscleGroup.fromJson(muscle as String))
      .toList();

  final int id;
  final String name;
  final Equipment? equipment;
  final List<MuscleGroup> primaryMuscles;
  final List<MuscleGroup> secondaryMuscles;
  final bool equipmentGuessed;
  final bool musclesGuessed;
}

class HevyWorkoutImportResult {
  const HevyWorkoutImportResult({
    required this.activitiesCreated,
    required this.exercisesCreated,
    this.createdExercises = const [],
  });

  factory HevyWorkoutImportResult.fromJson(Map<String, dynamic> json) => HevyWorkoutImportResult(
    activitiesCreated: json['activities_created'] as int,
    exercisesCreated: json['exercises_created'] as int,
    createdExercises: (json['created_exercises'] as List<dynamic>? ?? const [])
        .map((exercise) => ImportedExercise.fromJson(exercise as Map<String, dynamic>))
        .toList(),
  );

  final int activitiesCreated;
  final int exercisesCreated;

  /// The custom exercises created by this import, to be reviewed -- empty
  /// when every exercise matched an existing one (and for an older backend).
  final List<ImportedExercise> createdExercises;
}

class HevyMeasurementImportResult {
  const HevyMeasurementImportResult({required this.measurementsCreated});

  factory HevyMeasurementImportResult.fromJson(Map<String, dynamic> json) =>
      HevyMeasurementImportResult(measurementsCreated: json['measurements_created'] as int);

  final int measurementsCreated;
}
