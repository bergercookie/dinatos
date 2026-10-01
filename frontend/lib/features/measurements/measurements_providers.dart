import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/measurement.dart';
import 'measurements_repository.dart';

final measurementListProvider = FutureProvider.autoDispose<List<BodyMeasurement>>((ref) {
  return ref.watch(measurementsRepositoryProvider).list();
});

final measurementProvider = FutureProvider.autoDispose.family<BodyMeasurement, int>((ref, id) {
  return ref.watch(measurementsRepositoryProvider).get(id);
});
