import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/measurement.dart';
import 'measurements_repository.dart';

final measurementListProvider = FutureProvider.autoDispose<List<BodyMeasurement>>((ref) {
  return ref.watch(measurementsRepositoryProvider).list();
});
