/// One dated set of measurements; every value but the date is optional, so
/// an entry holds only what was measured that day. The fields fall into three
/// groups -- the basics and what a smart scale reports overall (weight, fat %,
/// muscle and bone mass, water, BMI, ...), the scale's segmental analysis
/// (fat % and muscle mass of each arm, leg and the trunk), and tape
/// measurements -- which the form shows as separate sections.
class BodyMeasurement {
  const BodyMeasurement({
    this.id,
    required this.measuredAt,
    this.weightKg,
    this.fatPercent,
    this.muscleMassKg,
    this.boneMassKg,
    this.bmi,
    this.dciKcal,
    this.metabolicAge,
    this.waterPercent,
    this.visceralFat,
    this.rightArmFatPercent,
    this.rightArmMuscleKg,
    this.leftArmFatPercent,
    this.leftArmMuscleKg,
    this.rightLegFatPercent,
    this.rightLegMuscleKg,
    this.leftLegFatPercent,
    this.leftLegMuscleKg,
    this.trunkFatPercent,
    this.trunkMuscleKg,
    this.neckCm,
    this.shoulderCm,
    this.chestCm,
    this.leftBicepCm,
    this.rightBicepCm,
    this.leftForearmCm,
    this.rightForearmCm,
    this.abdomenCm,
    this.waistCm,
    this.hipsCm,
    this.leftThighCm,
    this.rightThighCm,
    this.leftCalfCm,
    this.rightCalfCm,
  });

  factory BodyMeasurement.fromJson(Map<String, dynamic> json) => BodyMeasurement(
    id: json['id'] as int?,
    measuredAt: DateTime.parse(json['measured_at'] as String),
    weightKg: (json['weight_kg'] as num?)?.toDouble(),
    fatPercent: (json['fat_percent'] as num?)?.toDouble(),
    muscleMassKg: (json['muscle_mass_kg'] as num?)?.toDouble(),
    boneMassKg: (json['bone_mass_kg'] as num?)?.toDouble(),
    bmi: (json['bmi'] as num?)?.toDouble(),
    dciKcal: (json['dci_kcal'] as num?)?.toInt(),
    metabolicAge: (json['metabolic_age'] as num?)?.toInt(),
    waterPercent: (json['water_percent'] as num?)?.toDouble(),
    visceralFat: (json['visceral_fat'] as num?)?.toDouble(),
    rightArmFatPercent: (json['right_arm_fat_percent'] as num?)?.toDouble(),
    rightArmMuscleKg: (json['right_arm_muscle_kg'] as num?)?.toDouble(),
    leftArmFatPercent: (json['left_arm_fat_percent'] as num?)?.toDouble(),
    leftArmMuscleKg: (json['left_arm_muscle_kg'] as num?)?.toDouble(),
    rightLegFatPercent: (json['right_leg_fat_percent'] as num?)?.toDouble(),
    rightLegMuscleKg: (json['right_leg_muscle_kg'] as num?)?.toDouble(),
    leftLegFatPercent: (json['left_leg_fat_percent'] as num?)?.toDouble(),
    leftLegMuscleKg: (json['left_leg_muscle_kg'] as num?)?.toDouble(),
    trunkFatPercent: (json['trunk_fat_percent'] as num?)?.toDouble(),
    trunkMuscleKg: (json['trunk_muscle_kg'] as num?)?.toDouble(),
    neckCm: (json['neck_cm'] as num?)?.toDouble(),
    shoulderCm: (json['shoulder_cm'] as num?)?.toDouble(),
    chestCm: (json['chest_cm'] as num?)?.toDouble(),
    leftBicepCm: (json['left_bicep_cm'] as num?)?.toDouble(),
    rightBicepCm: (json['right_bicep_cm'] as num?)?.toDouble(),
    leftForearmCm: (json['left_forearm_cm'] as num?)?.toDouble(),
    rightForearmCm: (json['right_forearm_cm'] as num?)?.toDouble(),
    abdomenCm: (json['abdomen_cm'] as num?)?.toDouble(),
    waistCm: (json['waist_cm'] as num?)?.toDouble(),
    hipsCm: (json['hips_cm'] as num?)?.toDouble(),
    leftThighCm: (json['left_thigh_cm'] as num?)?.toDouble(),
    rightThighCm: (json['right_thigh_cm'] as num?)?.toDouble(),
    leftCalfCm: (json['left_calf_cm'] as num?)?.toDouble(),
    rightCalfCm: (json['right_calf_cm'] as num?)?.toDouble(),
  );

  final int? id;
  final DateTime measuredAt;
  final double? weightKg;
  final double? fatPercent;
  final double? muscleMassKg;
  final double? boneMassKg;
  final double? bmi;
  final int? dciKcal;
  final int? metabolicAge;
  final double? waterPercent;
  final double? visceralFat;
  final double? rightArmFatPercent;
  final double? rightArmMuscleKg;
  final double? leftArmFatPercent;
  final double? leftArmMuscleKg;
  final double? rightLegFatPercent;
  final double? rightLegMuscleKg;
  final double? leftLegFatPercent;
  final double? leftLegMuscleKg;
  final double? trunkFatPercent;
  final double? trunkMuscleKg;
  final double? neckCm;
  final double? shoulderCm;
  final double? chestCm;
  final double? leftBicepCm;
  final double? rightBicepCm;
  final double? leftForearmCm;
  final double? rightForearmCm;
  final double? abdomenCm;
  final double? waistCm;
  final double? hipsCm;
  final double? leftThighCm;
  final double? rightThighCm;
  final double? leftCalfCm;
  final double? rightCalfCm;

  Map<String, dynamic> toJson() => {
    'measured_at': measuredAt.toUtc().toIso8601String(),
    'weight_kg': weightKg,
    'fat_percent': fatPercent,
    'muscle_mass_kg': muscleMassKg,
    'bone_mass_kg': boneMassKg,
    'bmi': bmi,
    'dci_kcal': dciKcal,
    'metabolic_age': metabolicAge,
    'water_percent': waterPercent,
    'visceral_fat': visceralFat,
    'right_arm_fat_percent': rightArmFatPercent,
    'right_arm_muscle_kg': rightArmMuscleKg,
    'left_arm_fat_percent': leftArmFatPercent,
    'left_arm_muscle_kg': leftArmMuscleKg,
    'right_leg_fat_percent': rightLegFatPercent,
    'right_leg_muscle_kg': rightLegMuscleKg,
    'left_leg_fat_percent': leftLegFatPercent,
    'left_leg_muscle_kg': leftLegMuscleKg,
    'trunk_fat_percent': trunkFatPercent,
    'trunk_muscle_kg': trunkMuscleKg,
    'neck_cm': neckCm,
    'shoulder_cm': shoulderCm,
    'chest_cm': chestCm,
    'left_bicep_cm': leftBicepCm,
    'right_bicep_cm': rightBicepCm,
    'left_forearm_cm': leftForearmCm,
    'right_forearm_cm': rightForearmCm,
    'abdomen_cm': abdomenCm,
    'waist_cm': waistCm,
    'hips_cm': hipsCm,
    'left_thigh_cm': leftThighCm,
    'right_thigh_cm': rightThighCm,
    'left_calf_cm': leftCalfCm,
    'right_calf_cm': rightCalfCm,
  };
}
