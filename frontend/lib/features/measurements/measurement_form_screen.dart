import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../models/measurement.dart';
import 'measurements_providers.dart';
import 'measurements_repository.dart';

class MeasurementFormScreen extends ConsumerStatefulWidget {
  const MeasurementFormScreen({super.key});

  @override
  ConsumerState<MeasurementFormScreen> createState() => _MeasurementFormScreenState();
}

/// One controller per numeric field, keyed the same as the model's
/// constructor parameters -- 16 near-identical body-part measurements are
/// inherent to this schema, not something worth abstracting away from a
/// user's perspective (each is independently optional and editable).
class _MeasurementFormScreenState extends ConsumerState<MeasurementFormScreen> {
  DateTime _measuredAt = DateTime.now();
  final _controllers = {for (final field in _fields) field: TextEditingController()};
  bool _submitting = false;
  String? _error;

  static const _fields = [
    'weightKg',
    'fatPercent',
    'neckCm',
    'shoulderCm',
    'chestCm',
    'leftBicepCm',
    'rightBicepCm',
    'leftForearmCm',
    'rightForearmCm',
    'abdomenCm',
    'waistCm',
    'hipsCm',
    'leftThighCm',
    'rightThighCm',
    'leftCalfCm',
    'rightCalfCm',
  ];

  static const _labels = {
    'weightKg': 'Weight (kg)',
    'fatPercent': 'Body fat (%)',
    'neckCm': 'Neck (cm)',
    'shoulderCm': 'Shoulders (cm)',
    'chestCm': 'Chest (cm)',
    'leftBicepCm': 'Left bicep (cm)',
    'rightBicepCm': 'Right bicep (cm)',
    'leftForearmCm': 'Left forearm (cm)',
    'rightForearmCm': 'Right forearm (cm)',
    'abdomenCm': 'Abdomen (cm)',
    'waistCm': 'Waist (cm)',
    'hipsCm': 'Hips (cm)',
    'leftThighCm': 'Left thigh (cm)',
    'rightThighCm': 'Right thigh (cm)',
    'leftCalfCm': 'Left calf (cm)',
    'rightCalfCm': 'Right calf (cm)',
  };

  double? _value(String field) => double.tryParse(_controllers[field]!.text);

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _measuredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _measuredAt = picked);
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final measurement = BodyMeasurement(
      measuredAt: _measuredAt,
      weightKg: _value('weightKg'),
      fatPercent: _value('fatPercent'),
      neckCm: _value('neckCm'),
      shoulderCm: _value('shoulderCm'),
      chestCm: _value('chestCm'),
      leftBicepCm: _value('leftBicepCm'),
      rightBicepCm: _value('rightBicepCm'),
      leftForearmCm: _value('leftForearmCm'),
      rightForearmCm: _value('rightForearmCm'),
      abdomenCm: _value('abdomenCm'),
      waistCm: _value('waistCm'),
      hipsCm: _value('hipsCm'),
      leftThighCm: _value('leftThighCm'),
      rightThighCm: _value('rightThighCm'),
      leftCalfCm: _value('leftCalfCm'),
      rightCalfCm: _value('rightCalfCm'),
    );
    try {
      await ref.read(measurementsRepositoryProvider).create(measurement);
      ref.invalidate(measurementListProvider);
      if (mounted) context.pop();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New measurement')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date'),
            subtitle: Text(
              '${_measuredAt.year}-${_measuredAt.month.toString().padLeft(2, '0')}-'
              '${_measuredAt.day.toString().padLeft(2, '0')}',
            ),
            trailing: const Icon(Icons.edit_calendar),
            onTap: _pickDate,
          ),
          const SizedBox(height: 8),
          for (final field in _fields)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: TextField(
                controller: _controllers[field],
                decoration: InputDecoration(labelText: _labels[field]),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: _submitting ? null : _submit, child: const Text('Save')),
        ],
      ),
    );
  }
}
