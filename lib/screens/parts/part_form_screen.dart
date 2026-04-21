import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/part.dart';
import 'package:saturday_app/providers/parts_provider.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';

class PartFormScreen extends ConsumerStatefulWidget {
  final String? partId;

  /// Seed data for duplicating a part (creates a new part, not an edit)
  final Part? initialPart;

  const PartFormScreen({super.key, this.partId, this.initialPart});

  @override
  ConsumerState<PartFormScreen> createState() => _PartFormScreenState();
}

class _PartFormScreenState extends ConsumerState<PartFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _partNumberController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _reorderThresholdController = TextEditingController();

  PartType _partType = PartType.rawMaterial;
  PartCategory _category = PartCategory.other;
  UnitOfMeasure _unitOfMeasure = UnitOfMeasure.each;
  bool _isLoading = false;
  bool _initialized = false;

  bool get _isEditing => widget.partId != null;

  @override
  void dispose() {
    _nameController.dispose();
    _partNumberController.dispose();
    _descriptionController.dispose();
    _reorderThresholdController.dispose();
    super.dispose();
  }

  void _initFromPart(Part part) {
    if (_initialized) return;
    _initialized = true;
    _nameController.text = part.name;
    _partNumberController.text = part.partNumber;
    _descriptionController.text = part.description ?? '';
    _reorderThresholdController.text =
        part.reorderThreshold?.toString() ?? '';
    _partType = part.partType;
    _category = part.category;
    _unitOfMeasure = part.unitOfMeasure;
  }

  @override
  Widget build(BuildContext context) {
    // Seed fields from initialPart (duplicate mode)
    if (widget.initialPart != null && !_initialized) {
      _initFromPart(widget.initialPart!);
    }

    if (_isEditing) {
      final partAsync = ref.watch(partDetailProvider(widget.partId!));
      return partAsync.when(
        data: (part) {
          if (part == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Edit Part')),
              body: const Center(child: Text('Part not found')),
            );
          }
          _initFromPart(part);
          return _buildForm(context);
        },
        loading: () => Scaffold(
          appBar: AppBar(title: const Text('Edit Part')),
          body: const LoadingIndicator(message: 'Loading...'),
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Edit Part')),
          body: Center(child: Text('Error: $e')),
        ),
      );
    }
    return _buildForm(context);
  }

  Widget _buildForm(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing
            ? 'Edit Part'
            : widget.initialPart != null
                ? 'Duplicate Part'
                : 'New Part'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  hintText: 'e.g., Walnut Board 4/4',
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _partNumberController,
                decoration: const InputDecoration(
                  labelText: 'Part Number *',
                  hintText: 'e.g., SAT-WD-001',
                ),
                validator: (v) => v == null || v.isEmpty
                    ? 'Part number is required'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Optional description...',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<PartType>(
                value: _partType,
                decoration: const InputDecoration(labelText: 'Part Type'),
                items: PartType.values
                    .map((t) => DropdownMenuItem(
                        value: t, child: Text(t.displayName)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _partType = v);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<PartCategory>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: PartCategory.values
                    .map((c) => DropdownMenuItem(
                        value: c, child: Text(c.displayName)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _category = v);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<UnitOfMeasure>(
                value: _unitOfMeasure,
                decoration:
                    const InputDecoration(labelText: 'Unit of Measure'),
                items: UnitOfMeasure.values
                    .map((u) => DropdownMenuItem(
                        value: u, child: Text(u.displayName)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _unitOfMeasure = v);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reorderThresholdController,
                decoration: const InputDecoration(
                  labelText: 'Reorder Threshold (optional)',
                  hintText: 'Low stock alert level',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_isEditing ? 'Save Changes' : 'Create Part'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final management = ref.read(partsManagementProvider);
      final threshold = _reorderThresholdController.text.isNotEmpty
          ? double.tryParse(_reorderThresholdController.text)
          : null;

      if (_isEditing) {
        await management.updatePart(
          widget.partId!,
          name: _nameController.text,
          partNumber: _partNumberController.text,
          description: _descriptionController.text.isNotEmpty
              ? _descriptionController.text
              : null,
          partType: _partType,
          category: _category,
          unitOfMeasure: _unitOfMeasure,
          reorderThreshold: threshold,
        );
      } else {
        await management.createPart(
          name: _nameController.text,
          partNumber: _partNumberController.text,
          description: _descriptionController.text.isNotEmpty
              ? _descriptionController.text
              : null,
          partType: _partType,
          category: _category,
          unitOfMeasure: _unitOfMeasure,
          reorderThreshold: threshold,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Part updated' : 'Part created'),
            backgroundColor: SaturdayColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: SaturdayColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
