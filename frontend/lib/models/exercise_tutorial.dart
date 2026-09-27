/// A GIF plus instructions/muscles/equipment for one exercise, from
/// whichever provider the backend has active (see
/// docs/architecture.md's "Exercise tutorials") -- `source` says which,
/// but the shape is otherwise identical either way.
class ExerciseTutorial {
  const ExerciseTutorial({
    required this.source,
    required this.gifUrls,
    required this.instructions,
    this.equipment,
    required this.primaryMuscles,
    required this.secondaryMuscles,
  });

  factory ExerciseTutorial.fromJson(Map<String, dynamic> json) => ExerciseTutorial(
    source: json['source'] as String,
    gifUrls: (json['gif_urls'] as List<dynamic>).cast<String>(),
    instructions: (json['instructions'] as List<dynamic>).cast<String>(),
    equipment: json['equipment'] as String?,
    primaryMuscles: (json['primary_muscles'] as List<dynamic>).cast<String>(),
    secondaryMuscles: (json['secondary_muscles'] as List<dynamic>).cast<String>(),
  );

  final String source;
  final List<String> gifUrls;
  final List<String> instructions;
  final String? equipment;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
}
