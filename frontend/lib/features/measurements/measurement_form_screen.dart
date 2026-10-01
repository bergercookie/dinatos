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

/// One controller per numeric field, keyed the same as the model's
/// constructor parameters -- 16 near-identical body-part measurements are
/// inherent to this schema, not something worth abstracting away from a
/// user's perspective (each is independently optional and editable).
class _MeasurementFormScreenState extends ConsumerState<MeasurementFormScreen> {
  DateTime _measuredAt = DateTime.now();
  final _controllers = {for (final field in _fields) field: TextEditingController()};
  bool _submitting = false;
  String? _error;
  bool _loadedInitialValues = false;

  bool get _isEditing => widget.measurementId != null;

  void _loadFrom(BodyMeasurement measurement) {
    if (_loadedInitialValues) return;
    _loadedInitialValues = true;
    _measuredAt = measurement.measuredAt.toLocal();
    _controllers['weightKg']!.text = measurement.weightKg?.toString() ?? '';
    _controllers['fatPercent']!.text = measurement.fatPercent?.toString() ?? '';
    _controllers['neckCm']!.text = measurement.neckCm?.toString() ?? '';
    _controllers['shoulderCm']!.text = measurement.shoulderCm?.toString() ?? '';
    _controllers['chestCm']!.text = measurement.chestCm?.toString() ?? '';
    _controllers['leftBicepCm']!.text = measurement.leftBicepCm?.toString() ?? '';
    _controllers['rightBicepCm']!.text = measurement.rightBicepCm?.toString() ?? '';
    _controllers['leftForearmCm']!.text = measurement.leftForearmCm?.toString() ?? '';
    _controllers['rightForearmCm']!.text = measurement.rightForearmCm?.toString() ?? '';
    _controllers['abdomenCm']!.text = measurement.abdomenCm?.toString() ?? '';
    _controllers['waistCm']!.text = measurement.waistCm?.toString() ?? '';
    _controllers['hipsCm']!.text = measurement.hipsCm?.toString() ?? '';
    _controllers['leftThighCm']!.text = measurement.leftThighCm?.toString() ?? '';
    _controllers['rightThighCm']!.text = measurement.rightThighCm?.toString() ?? '';
    _controllers['leftCalfCm']!.text = measurement.leftCalfCm?.toString() ?? '';
    _controllers['rightCalfCm']!.text = measurement.rightCalfCm?.toString() ?? '';
  }

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
