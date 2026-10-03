enum UnitSystem {
  metric,
  imperial;

  static UnitSystem fromJson(String value) => UnitSystem.values.byName(value);

  String toJson() => name;
}

class Profile {
  const Profile({required this.heightCm, required this.unitSystem, this.hasWorkoutxApiKey = false});

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    heightCm: (json['height_cm'] as num?)?.toDouble(),
    unitSystem: UnitSystem.fromJson(json['unit_system'] as String),
    hasWorkoutxApiKey: json['has_workoutx_api_key'] as bool? ?? false,
  );

  final double? heightCm;
  final UnitSystem unitSystem;

  /// Whether this user has saved their own WorkoutX API key. The key itself
  /// is write-only: the backend never sends it back, and it's deliberately
  /// not part of [toJson], so saving the profile form never touches it (see
  /// `ProfileRepository.setWorkoutxApiKey`).
  final bool hasWorkoutxApiKey;

  Map<String, dynamic> toJson() => {'height_cm': heightCm, 'unit_system': unitSystem.toJson()};

  Profile copyWith({double? heightCm, UnitSystem? unitSystem, bool? hasWorkoutxApiKey}) => Profile(
    heightCm: heightCm ?? this.heightCm,
    unitSystem: unitSystem ?? this.unitSystem,
    hasWorkoutxApiKey: hasWorkoutxApiKey ?? this.hasWorkoutxApiKey,
  );
}
