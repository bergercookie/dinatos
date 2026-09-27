class HevyWorkoutImportResult {
  const HevyWorkoutImportResult({required this.activitiesCreated, required this.exercisesCreated});

  factory HevyWorkoutImportResult.fromJson(Map<String, dynamic> json) => HevyWorkoutImportResult(
    activitiesCreated: json['activities_created'] as int,
    exercisesCreated: json['exercises_created'] as int,
  );

  final int activitiesCreated;
  final int exercisesCreated;
}

class HevyMeasurementImportResult {
  const HevyMeasurementImportResult({required this.measurementsCreated});

  factory HevyMeasurementImportResult.fromJson(Map<String, dynamic> json) =>
      HevyMeasurementImportResult(measurementsCreated: json['measurements_created'] as int);

  final int measurementsCreated;
}
