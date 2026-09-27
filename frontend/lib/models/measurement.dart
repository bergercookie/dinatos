class BodyMeasurement {
  const BodyMeasurement({
    this.id,
    required this.measuredAt,
    this.weightKg,
    this.fatPercent,
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
    id: json['id'] as int,
    measuredAt: DateTime.parse(json['measured_at'] as String),
    weightKg: (json['weight_kg'] as num?)?.toDouble(),
    fatPercent: (json['fat_percent'] as num?)?.toDouble(),
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
