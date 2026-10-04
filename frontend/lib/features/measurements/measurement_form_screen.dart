import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/async_value_view.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/responsive_body.dart';
import '../../models/measurement.dart';
import 'measurements_providers.dart';
import 'measurements_repository.dart';

/// Create when [measurementId] is null, otherwise edit (and `PUT`-replace)
/// that measurement.
class MeasurementFormScreen extends ConsumerStatefulWidget {
  const MeasurementFormScreen({super.key, this.measurementId});

  final int? measurementId;

  @override
  ConsumerState<MeasurementFormScreen> createState() => _MeasurementFormScreenState();
}

/// One labelled number field of the form; [key] is the field's name in the
/// API (and in [BodyMeasurement.toJson]), which is also what keys its
/// controller.
class _FieldSpec {
  const _FieldSpec(this.key, this.label, {this.whole = false});

  final String key;
  final String label;

  /// A whole number (years, kcal): no decimal point on the keyboard.
  final bool whole;
}

/// A titled group of fields. Storage is flat (one row per entry), but the
/// three groups are different kinds of entry: a smart-scale weigh-in fills
/// the first two, a tape session only the last.
class _Section {
  const _Section(this.title, this.hint, this.fields);

  final String title;
  final String hint;
  final List<_FieldSpec> fields;
}

const _sections = [
  _Section('Body composition', 'Weight and the totals a smart scale reports.', [
    _FieldSpec('weight_kg', 'Weight (kg)'),
    _FieldSpec('fat_percent', 'Body fat (%)'),
    _FieldSpec('muscle_mass_kg', 'Muscle mass (kg)'),
    _FieldSpec('bone_mass_kg', 'Bone mass (kg)'),
    _FieldSpec('water_percent', 'Water (%)'),
    _FieldSpec('bmi', 'BMI'),
    _FieldSpec('visceral_fat', 'Visceral fat (rating)'),
    _FieldSpec('dci_kcal', 'DCI (kcal)', whole: true),
    _FieldSpec('metabolic_age', 'Metabolic age (years)', whole: true),
  ]),
  _Section('Segmental analysis', 'Fat and muscle of each limb and the trunk, from a smart scale.', [
    _FieldSpec('right_arm_fat_percent', 'Right arm fat (%)'),
    _FieldSpec('right_arm_muscle_kg', 'Right arm muscle (kg)'),
    _FieldSpec('left_arm_fat_percent', 'Left arm fat (%)'),
    _FieldSpec('left_arm_muscle_kg', 'Left arm muscle (kg)'),
    _FieldSpec('right_leg_fat_percent', 'Right leg fat (%)'),
    _FieldSpec('right_leg_muscle_kg', 'Right leg muscle (kg)'),
    _FieldSpec('left_leg_fat_percent', 'Left leg fat (%)'),
    _FieldSpec('left_leg_muscle_kg', 'Left leg muscle (kg)'),
    _FieldSpec('trunk_fat_percent', 'Trunk fat (%)'),
    _FieldSpec('trunk_muscle_kg', 'Trunk muscle (kg)'),
  ]),
  _Section('Tape measurements', 'Circumferences, measured with a tape.', [
    _FieldSpec('neck_cm', 'Neck (cm)'),
    _FieldSpec('shoulder_cm', 'Shoulders (cm)'),
    _FieldSpec('chest_cm', 'Chest (cm)'),
    _FieldSpec('left_bicep_cm', 'Left bicep (cm)'),
    _FieldSpec('right_bicep_cm', 'Right bicep (cm)'),
    _FieldSpec('left_forearm_cm', 'Left forearm (cm)'),
    _FieldSpec('right_forearm_cm', 'Right forearm (cm)'),
    _FieldSpec('abdomen_cm', 'Abdomen (cm)'),
    _FieldSpec('waist_cm', 'Waist (cm)'),
    _FieldSpec('hips_cm', 'Hips (cm)'),
    _FieldSpec('left_thigh_cm', 'Left thigh (cm)'),
    _FieldSpec('right_thigh_cm', 'Right thigh (cm)'),
    _FieldSpec('left_calf_cm', 'Left calf (cm)'),
    _FieldSpec('right_calf_cm', 'Right calf (cm)'),
  ]),
];

final _allFields = [for (final section in _sections) ...section.fields];

class _MeasurementFormScreenState extends ConsumerState<MeasurementFormScreen> {
  DateTime _measuredAt = DateTime.now();
  final _controllers = {for (final field in _allFields) field.key: TextEditingController()};
  bool _submitting = false;
  String? _error;
  bool _loadedInitialValues = false;

  bool get _isEditing => widget.measurementId != null;

  void _loadFrom(BodyMeasurement measurement) {
    if (_loadedInitialValues) return;
    _loadedInitialValues = true;
    _measuredAt = measurement.measuredAt.toLocal();
    final json = measurement.toJson();
    for (final field in _allFields) {
      _controllers[field.key]!.text = json[field.key]?.toString() ?? '';
    }
  }

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
    final measurement = BodyMeasurement.fromJson({
      'measured_at': _measuredAt.toUtc().toIso8601String(),
      for (final field in _allFields) field.key: _value(field.key),
    });
    final repository = ref.read(measurementsRepositoryProvider);
    try {
      if (_isEditing) {
        await repository.replace(widget.measurementId!, measurement);
      } else {
        await repository.create(measurement);
      }
      ref.invalidate(measurementListProvider);
      if (mounted) context.pop();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _submitting = true);
    try {
      await ref.read(measurementsRepositoryProvider).delete(widget.measurementId!);
      ref.invalidate(measurementListProvider);
      if (mounted) context.pop();
    } on ApiException catch (error) {
      setState(() {
        _error = error.message;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEditing ? 'Edit measurement' : 'New measurement';
    if (!_isEditing) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ResponsiveBody(child: _buildForm(context)),
      );
    }
    final measurementAsync = ref.watch(measurementProvider(widget.measurementId!));
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Delete measurement',
            icon: const Icon(Icons.delete_outline),
            onPressed: _submitting ? null : _delete,
          ),
        ],
      ),
      body: ResponsiveBody(
        child: AsyncValueView(
          value: measurementAsync,
          builder: (context, measurement) {
            _loadFrom(measurement);
            return _buildForm(context);
          },
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return ListView(
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
        for (final section in _sections) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(section.title, style: Theme.of(context).textTheme.titleMedium),
          Text(
            section.hint,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final field in section.fields)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: TextField(
                controller: _controllers[field.key],
                decoration: InputDecoration(labelText: field.label),
                keyboardType: TextInputType.numberWithOptions(decimal: !field.whole),
              ),
            ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          ErrorBanner(message: _error!),
        ],
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
