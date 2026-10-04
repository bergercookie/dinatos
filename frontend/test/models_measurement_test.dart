import 'package:dinatos_frontend/models/measurement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('smart-scale fields survive a JSON round trip, whole numbers as ints', () {
    final json = {
      'id': 3,
      'measured_at': '2026-01-01T00:00:00Z',
      'weight_kg': 70.5,
      'muscle_mass_kg': 55.1,
      'bone_mass_kg': 2.9,
      'bmi': 22.4,
      'dci_kcal': 2410,
      'metabolic_age': 27,
      'water_percent': 57.5,
      'visceral_fat': 6,
      'right_arm_fat_percent': 12.1,
      'right_arm_muscle_kg': 3.2,
      'left_arm_fat_percent': 12.4,
      'left_arm_muscle_kg': 3.1,
      'right_leg_fat_percent': 14,
      'right_leg_muscle_kg': 9.4,
      'left_leg_fat_percent': 14.2,
      'left_leg_muscle_kg': 9.3,
      'trunk_fat_percent': 16.3,
      'trunk_muscle_kg': 27.8,
    };
    final measurement = BodyMeasurement.fromJson(json);

    expect(measurement.muscleMassKg, 55.1);
    expect(measurement.dciKcal, 2410);
    expect(measurement.metabolicAge, 27);
    expect(measurement.visceralFat, 6.0);
    expect(measurement.rightLegFatPercent, 14.0);
    expect(measurement.trunkMuscleKg, 27.8);

    // Every number comes back out as it went in (the id is the API's, not sent).
    final out = measurement.toJson();
    for (final entry in json.entries) {
      if (entry.key == 'id' || entry.key == 'measured_at') continue;
      expect(out[entry.key], (entry.value as num), reason: entry.key);
    }
    expect(out['dci_kcal'], isA<int>());
    expect(out['metabolic_age'], isA<int>());
  });

  test('an entry without them leaves them null, and needs no id', () {
    final measurement = BodyMeasurement.fromJson({
      'measured_at': '2026-01-01T00:00:00Z',
      'waist_cm': 80,
    });
    expect(measurement.id, isNull);
    expect(measurement.muscleMassKg, isNull);
    expect(measurement.trunkFatPercent, isNull);
    expect(measurement.waistCm, 80.0);
  });
}
