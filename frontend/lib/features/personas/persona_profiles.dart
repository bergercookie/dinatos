/// The reference data behind the "which athlete do you resemble" page: a few
/// athlete personas, each described by a typical body and a typical training
/// mix. These are rough, hand-picked archetypes -- the point is a fun,
/// explainable comparison, not sports science -- so every number here is
/// deliberately round and easy to read and argue with.
library;

/// One thing measured about a body. Ratios (to height, to waist) rather than
/// raw centimetres, so a short and a tall person with the same build compare
/// alike.
enum BodyFeature {
  height(
    label: 'Height',
    unit: 'cm',
    decimals: 0,
    weight: 0.5,
    hint: 'Taller frames suit throwing and swimming; shorter ones suit lifting and gymnastics.',
  ),
  ffmi(
    label: 'Muscularity (FFMI)',
    unit: '',
    decimals: 1,
    weight: 1,
    hint: 'Fat-free mass relative to height: lean mass in kg divided by height in metres squared.',
  ),
  fatPercent(
    label: 'Body fat',
    unit: '%',
    decimals: 0,
    weight: 1,
    hint: 'Endurance and gymnastics sports tend to be very lean.',
  ),
  waistToHeight(
    label: 'Waist-to-height',
    unit: '',
    decimals: 2,
    weight: 1,
    hint: 'Waist circumference divided by height; lower means a tighter midsection.',
  ),
  shoulderToWaist(
    label: 'Shoulder-to-waist',
    unit: '',
    decimals: 2,
    weight: 1,
    hint: 'Shoulder circumference divided by waist; the classic V-taper.',
  ),
  thighToHeight(
    label: 'Thigh-to-height',
    unit: '',
    decimals: 2,
    weight: 1,
    hint: 'Thigh circumference divided by height; a proxy for leg size.',
  ),
  armToHeight(
    label: 'Arm-to-height',
    unit: '',
    decimals: 2,
    weight: 1,
    hint: 'Biceps circumference divided by height; a proxy for arm size.',
  ),
  muscleIndex(
    label: 'Muscle mass index',
    unit: '',
    decimals: 1,
    weight: 1,
    hint:
        'The scale\'s muscle mass divided by height in metres squared. Scales define '
        '"muscle" differently, so compare readings from the same one.',
  ),
  lowerBodyMuscle(
    label: 'Lower-body muscle share',
    unit: '%',
    decimals: 0,
    weight: 1,
    percent: true,
    hint:
        'Leg muscle as a share of arm plus leg muscle, from the scale\'s segmental '
        'readout: sprinters and lifters are leg-heavy, gymnasts and bodybuilders '
        'more upper-body.',
  );

  const BodyFeature({
    required this.label,
    required this.unit,
    required this.decimals,
    required this.weight,
    required this.hint,
    this.percent = false,
  });

  final String label;
  final String unit;
  final int decimals;

  /// How much this feature counts towards a persona's body match, relative
  /// to the others. Height is a weak signal: plenty of great athletes are
  /// not the typical height for their sport.
  final double weight;
  final String hint;

  /// The value is a fraction (0 to 1) that reads better as a percentage.
  final bool percent;

  String format(double value) =>
      '${(percent ? value * 100 : value).toStringAsFixed(decimals)}${unit.isEmpty ? '' : unit}';
}

/// A persona's typical value for a [BodyFeature]. [tolerance] is how far off
/// a person can be and still count as "close" (one tolerance away scores
/// about 60%, two about 14%).
class BodyTarget {
  const BodyTarget(this.ideal, this.tolerance);

  final double ideal;
  final double tolerance;
}

/// What a set of training can be mostly about. Every working set the person
/// logs is put in exactly one of these (see `classifySet` in
/// `persona_scoring.dart`), so a training history becomes a mix that adds up
/// to 100%.
enum TrainingFocus {
  maxStrength(label: 'Max strength', description: 'Heavy weights for 1-5 reps.'),
  muscleBuilding(label: 'Muscle building', description: 'Moderate weights for 6-15 reps.'),
  explosive(
    label: 'Explosive power',
    description: 'Jumps, throws, sprints, cleans, snatches and swings.',
  ),
  endurance(
    label: 'Endurance',
    description: 'Running, cycling and other long efforts, or lots of light reps.',
  ),
  bodyweightSkill(
    label: 'Bodyweight & skill',
    description: 'Pull-ups, dips, holds and other bodyweight work.',
  );

  const TrainingFocus({required this.label, required this.description});

  final String label;
  final String description;
}

class Persona {
  const Persona({
    required this.id,
    required this.name,
    required this.shortName,
    required this.summary,
    required this.body,
    required this.training,
  });

  final String id;
  final String name;

  /// What the radar chart prints at the end of this persona's spoke.
  final String shortName;

  /// One sentence on what this athlete is like, shown on the detail card.
  final String summary;
  final Map<BodyFeature, BodyTarget> body;

  /// Fractions of working sets per [TrainingFocus]; sums to 1.
  final Map<TrainingFocus, double> training;
}

/// The built-in personas. They are tuned for an adult male build on purpose
/// (the app doesn't know anyone's sex), which is called out on the page.
const personas = <Persona>[
  Persona(
    id: 'sprinter',
    name: 'Elite sprinter',
    shortName: 'Sprinter',
    summary: 'Powerful, lean and tight at the waist, with big legs for their height.',
    body: {
      BodyFeature.height: BodyTarget(180, 12),
      BodyFeature.ffmi: BodyTarget(22.5, 2.5),
      BodyFeature.fatPercent: BodyTarget(8, 4),
      BodyFeature.waistToHeight: BodyTarget(0.42, 0.04),
      BodyFeature.shoulderToWaist: BodyTarget(1.40, 0.15),
      BodyFeature.thighToHeight: BodyTarget(0.33, 0.04),
      BodyFeature.armToHeight: BodyTarget(0.19, 0.025),
      BodyFeature.muscleIndex: BodyTarget(19.5, 2.5),
      BodyFeature.lowerBodyMuscle: BodyTarget(0.77, 0.04),
    },
    training: {
      TrainingFocus.maxStrength: 0.25,
      TrainingFocus.muscleBuilding: 0.10,
      TrainingFocus.explosive: 0.40,
      TrainingFocus.endurance: 0.10,
      TrainingFocus.bodyweightSkill: 0.15,
    },
  ),
  Persona(
    id: 'distance_runner',
    name: 'Distance runner',
    shortName: 'Distance runner',
    summary: 'Light, very lean and narrow, with slim legs and arms built for efficiency.',
    body: {
      BodyFeature.height: BodyTarget(175, 10),
      BodyFeature.ffmi: BodyTarget(19, 2),
      BodyFeature.fatPercent: BodyTarget(7, 3.5),
      BodyFeature.waistToHeight: BodyTarget(0.41, 0.035),
      BodyFeature.shoulderToWaist: BodyTarget(1.30, 0.15),
      BodyFeature.thighToHeight: BodyTarget(0.28, 0.035),
      BodyFeature.armToHeight: BodyTarget(0.16, 0.025),
      BodyFeature.muscleIndex: BodyTarget(16.5, 2),
      BodyFeature.lowerBodyMuscle: BodyTarget(0.76, 0.04),
    },
    training: {
      TrainingFocus.maxStrength: 0.05,
      TrainingFocus.muscleBuilding: 0.05,
      TrainingFocus.explosive: 0.05,
      TrainingFocus.endurance: 0.75,
      TrainingFocus.bodyweightSkill: 0.10,
    },
  ),
  Persona(
    id: 'weightlifter',
    name: 'Olympic weightlifter',
    shortName: 'Weightlifter',
    summary: 'Compact and thick through the legs and trunk; strong and explosive.',
    body: {
      BodyFeature.height: BodyTarget(170, 12),
      BodyFeature.ffmi: BodyTarget(24, 3),
      BodyFeature.fatPercent: BodyTarget(12, 5),
      BodyFeature.waistToHeight: BodyTarget(0.47, 0.05),
      BodyFeature.shoulderToWaist: BodyTarget(1.40, 0.15),
      BodyFeature.thighToHeight: BodyTarget(0.35, 0.04),
      BodyFeature.armToHeight: BodyTarget(0.20, 0.03),
      BodyFeature.muscleIndex: BodyTarget(21, 2.5),
      BodyFeature.lowerBodyMuscle: BodyTarget(0.76, 0.04),
    },
    training: {
      TrainingFocus.maxStrength: 0.50,
      TrainingFocus.muscleBuilding: 0.15,
      TrainingFocus.explosive: 0.30,
      TrainingFocus.endurance: 0.00,
      TrainingFocus.bodyweightSkill: 0.05,
    },
  ),
  Persona(
    id: 'powerlifter',
    name: 'Powerlifter',
    shortName: 'Powerlifter',
    summary: 'Thick and very strong: heavy squat, bench and deadlift, with little else.',
    body: {
      BodyFeature.height: BodyTarget(175, 12),
      BodyFeature.ffmi: BodyTarget(24, 3),
      BodyFeature.fatPercent: BodyTarget(15, 5),
      BodyFeature.waistToHeight: BodyTarget(0.50, 0.05),
      BodyFeature.shoulderToWaist: BodyTarget(1.30, 0.15),
      BodyFeature.thighToHeight: BodyTarget(0.35, 0.04),
      BodyFeature.armToHeight: BodyTarget(0.20, 0.03),
      BodyFeature.muscleIndex: BodyTarget(21.5, 2.5),
      BodyFeature.lowerBodyMuscle: BodyTarget(0.74, 0.04),
    },
    training: {
      TrainingFocus.maxStrength: 0.65,
      TrainingFocus.muscleBuilding: 0.25,
      TrainingFocus.explosive: 0.00,
      TrainingFocus.endurance: 0.00,
      TrainingFocus.bodyweightSkill: 0.10,
    },
  ),
  Persona(
    id: 'bodybuilder',
    name: 'Bodybuilder',
    shortName: 'Bodybuilder',
    summary: 'Maximum muscle with a very small waist: a pronounced V-taper and big limbs.',
    body: {
      BodyFeature.height: BodyTarget(178, 15),
      BodyFeature.ffmi: BodyTarget(25.5, 2.5),
      BodyFeature.fatPercent: BodyTarget(8, 4),
      BodyFeature.waistToHeight: BodyTarget(0.42, 0.05),
      BodyFeature.shoulderToWaist: BodyTarget(1.60, 0.15),
      BodyFeature.thighToHeight: BodyTarget(0.36, 0.04),
      BodyFeature.armToHeight: BodyTarget(0.23, 0.03),
      BodyFeature.muscleIndex: BodyTarget(22.5, 2.5),
      BodyFeature.lowerBodyMuscle: BodyTarget(0.7, 0.04),
    },
    training: {
      TrainingFocus.maxStrength: 0.10,
      TrainingFocus.muscleBuilding: 0.80,
      TrainingFocus.explosive: 0.00,
      TrainingFocus.endurance: 0.05,
      TrainingFocus.bodyweightSkill: 0.05,
    },
  ),
  Persona(
    id: 'gymnast',
    name: 'Gymnast',
    shortName: 'Gymnast',
    summary: 'Short, very lean and strong for their size, with wide shoulders over a tiny waist.',
    body: {
      BodyFeature.height: BodyTarget(166, 8),
      BodyFeature.ffmi: BodyTarget(22, 2.5),
      BodyFeature.fatPercent: BodyTarget(7, 3.5),
      BodyFeature.waistToHeight: BodyTarget(0.43, 0.04),
      BodyFeature.shoulderToWaist: BodyTarget(1.55, 0.15),
      BodyFeature.thighToHeight: BodyTarget(0.31, 0.04),
      BodyFeature.armToHeight: BodyTarget(0.20, 0.03),
      BodyFeature.muscleIndex: BodyTarget(19, 2.5),
      BodyFeature.lowerBodyMuscle: BodyTarget(0.68, 0.04),
    },
    training: {
      TrainingFocus.maxStrength: 0.15,
      TrainingFocus.muscleBuilding: 0.10,
      TrainingFocus.explosive: 0.15,
      TrainingFocus.endurance: 0.05,
      TrainingFocus.bodyweightSkill: 0.55,
    },
  ),
];
