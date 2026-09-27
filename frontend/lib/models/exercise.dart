class Exercise {
  const Exercise({
    this.id,
    required this.name,
    this.tracksWeight = true,
    this.tracksReps = true,
    this.tracksDistance = false,
    this.tracksDuration = false,
  });

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
    id: json['id'] as int,
    name: json['name'] as String,
    tracksWeight: json['tracks_weight'] as bool,
    tracksReps: json['tracks_reps'] as bool,
    tracksDistance: json['tracks_distance'] as bool,
    tracksDuration: json['tracks_duration'] as bool,
  );

  final int? id;
  final String name;
  final bool tracksWeight;
  final bool tracksReps;
  final bool tracksDistance;
  final bool tracksDuration;

  /// The subset of fields the create/update endpoints accept -- `id` is
  /// server-assigned, never sent back.
  Map<String, dynamic> toJson() => {
    'name': name,
    'tracks_weight': tracksWeight,
    'tracks_reps': tracksReps,
    'tracks_distance': tracksDistance,
    'tracks_duration': tracksDuration,
  };
}
