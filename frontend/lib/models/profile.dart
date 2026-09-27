enum UnitSystem {
  metric,
  imperial;

  static UnitSystem fromJson(String value) => UnitSystem.values.byName(value);

  String toJson() => name;
}

class Profile {
  const Profile({required this.heightCm, required this.unitSystem});

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    heightCm: (json['height_cm'] as num?)?.toDouble(),
    unitSystem: UnitSystem.fromJson(json['unit_system'] as String),
  );

  final double? heightCm;
  final UnitSystem unitSystem;

  Map<String, dynamic> toJson() => {'height_cm': heightCm, 'unit_system': unitSystem.toJson()};

  Profile copyWith({double? heightCm, UnitSystem? unitSystem}) =>
      Profile(heightCm: heightCm ?? this.heightCm, unitSystem: unitSystem ?? this.unitSystem);
}
