##

 Multiple Labels Implementation Guide

## Overview

This guide explains the implementation of multiple labels per production step, replacing the previous single-label design.

---

## Architecture Changes

### Database Schema

**New Table**: `step_labels`

```sql
CREATE TABLE public.step_labels (
  id UUID PRIMARY KEY,
  step_id UUID REFERENCES production_steps(id) ON DELETE CASCADE,
  label_text TEXT NOT NULL,
  label_order INTEGER NOT NULL,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

**Relationship**: One-to-Many (Step → Labels)
- Each production step can have 0 or more labels
- Labels are ordered by `label_order`
- Cascade delete when step is deleted

---

## Implementation Status

### ✅ Completed

1. **Database Migration** (`009_production_step_labels.sql`)
   - Created `step_labels` table
   - Added RLS policies
   - Added indexes for performance

2. **Models**
   - `StepLabel` model created
   - `ProductionStep` model cleaned (removed old fields)

3. **Repository** (`step_label_repository.dart`)
   - CRUD operations for labels
   - Batch create/update operations
   - Query by step ID with ordering

4. **Provider** (`step_label_provider.dart`)
   - Provider for fetching labels
   - Management provider for operations

---

## TODO: UI Implementation

### 1. Production Step Form Screen

**File**: `lib/screens/products/production_step_form_screen.dart`

#### Changes Needed:

**A. State Variables**
Replace:
```dart
final _labelTextController = TextEditingController();
bool _generateLabel = false;
```

With:
```dart
List<TextEditingController> _labelControllers = [];
List<String> _existingLabelIds = []; // For tracking which labels exist in DB
```

**B. Initialize from Existing Step**
```dart
@override
void initState() {
  super.initState();
  if (widget.step != null) {
    _nameController.text = widget.step!.name;
    _descriptionController.text = widget.step!.description ?? '';
    _selectedFileName = widget.step!.fileName;

    // Load existing labels
    _loadExistingLabels();
  }
}

Future<void> _loadExistingLabels() async {
  final labels = await ref.read(stepLabelsProvider(widget.step!.id).future);
  setState(() {
    for (final label in labels) {
      final controller = TextEditingController(text: label.labelText);
      _labelControllers.add(controller);
      _existingLabelIds.add(label.id);
    }
  });
}
```

**C. Replace Label Configuration Section**
```dart
// Label configuration section
Text(
  'Label Configuration',
  style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
),
const SizedBox(height: 8),
Text(
  'Add one or more labels to print when this step is completed. '
  'Example: "LEFT SIDE", "RIGHT SIDE"',
  style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: SaturdayColors.secondaryGrey,
      ),
),
const SizedBox(height: 16),

// Label list
..._labelControllers.asMap().entries.map((entry) {
  final index = entry.key;
  final controller = entry.value;

  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        // Label order badge
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: SaturdayColors.primaryDark,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Text field
        Expanded(
          child: TextFormField(
            controller: controller,
            decoration: InputDecoration(
              labelText: 'Label ${index + 1}',
              hintText: 'e.g., LEFT SIDE',
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter label text';
              }
              return null;
            },
          ),
        ),

        // Delete button
        IconButton(
          icon: const Icon(Icons.delete_outline),
          color: SaturdayColors.error,
          onPressed: () => _removeLabel(index),
        ),
      ],
    ),
  );
}).toList(),

// Add label button
OutlinedButton.icon(
  onPressed: _addLabel,
  icon: const Icon(Icons.add),
  label: const Text('Add Label'),
  style: OutlinedButton.styleFrom(
    padding: const EdgeInsets.all(16),
  ),
),
```

**D. Add/Remove Label Methods**
```dart
void _addLabel() {
  setState(() {
    _labelControllers.add(TextEditingController());
  });
}

void _removeLabel(int index) {
  setState(() {
    _labelControllers[index].dispose();
    _labelControllers.removeAt(index);
    if (index < _existingLabelIds.length) {
      _existingLabelIds.removeAt(index);
    }
  });
}
```

**E. Update Submit Handler**
```dart
Future<void> _handleSubmit() async {
  if (!_formKey.currentState!.validate()) {
    return;
  }

  setState(() {
    _isLoading = true;
  });

  try {
    final management = ref.read(productionStepManagementProvider);
    final labelManagement = ref.read(stepLabelManagementProvider);

    if (widget.step != null) {
      // Update existing step
      final updatedStep = widget.step!.copyWith(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        fileName: _selectedFileName,
      );

      await management.updateStep(
        updatedStep,
        file: _selectedFile,
        oldStep: widget.step,
      );

      // Update labels
      final labelTexts = _labelControllers
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      await labelManagement.updateLabelsForStep(
        widget.step!.id,
        labelTexts,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Production step updated'),
            backgroundColor: SaturdayColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } else {
      // Create new step
      final nextOrder = await management.getNextStepOrder(widget.product.id);

      final newStep = ProductionStep(
        id: '', // Will be generated
        productId: widget.product.id,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        stepOrder: nextOrder,
        fileName: _selectedFileName,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final createdStep = await management.createStep(newStep, file: _selectedFile);

      // Create labels
      final labelTexts = _labelControllers
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      if (labelTexts.isNotEmpty) {
        await labelManagement.batchCreateLabels(
          createdStep.id,
          labelTexts,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Production step created'),
            backgroundColor: SaturdayColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    }
  } catch (error) {
    setState(() {
      _isLoading = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save step: $error'),
          backgroundColor: SaturdayColors.error,
        ),
      );
    }
  }
}
```

**F. Dispose Controllers**
```dart
@override
void dispose() {
  _nameController.dispose();
  _descriptionController.dispose();
  for (final controller in _labelControllers) {
    controller.dispose();
  }
  super.dispose();
}
```

---

### 2. Complete Step Screen

**File**: `lib/screens/production/complete_step_screen.dart`

#### Changes Needed:

**A. Update Print Method**
Replace entire `_printStepLabel()` method with:

```dart
Future<void> _printAllStepLabels() async {
  setState(() {
    _isPrinting = true;
  });

  try {
    // Get unit data
    final unitAsync = ref.read(unitByIdProvider(widget.unitId));
    final unit = unitAsync.value;

    if (unit == null) {
      _showError('Unit data not available');
      return;
    }

    // Get product and variant info
    final productAsync = ref.read(productProvider(unit.productId));
    final product = productAsync.value;

    if (product == null) {
      _showError('Product data not available');
      return;
    }

    final variantAsync = ref.read(variantProvider(unit.variantId));
    final variant = variantAsync.value;

    if (variant == null) {
      _showError('Variant data not available');
      return;
    }

    // Get labels for this step
    final labelsAsync = await ref.read(stepLabelsProvider(widget.step.id).future);

    if (labelsAsync.isEmpty) {
      _showError('No labels configured for this step');
      return;
    }

    AppLogger.info('Printing ${labelsAsync.length} labels for step ${widget.step.name}');

    // Generate QR code once (used for all labels)
    final qrService = QRService();
    final qrImageData = await qrService.generateQRCode(
      unit.uuid,
      size: 512,
      embedLogo: true,
    );

    final printerService = PrinterService();
    int successCount = 0;
    int failCount = 0;

    // Print each label
    for (final label in labelsAsync) {
      try {
        // Generate label
        final labelData = await printerService.generateStepLabel(
          unit: unit,
          productName: product.name,
          variantName: variant.name,
          qrImageData: qrImageData,
          labelText: label.labelText,
        );

        // Print to configured printer
        final success = await printerService.printQRLabel(labelData);

        if (success) {
          successCount++;
          AppLogger.info('Printed label: ${label.labelText}');
        } else {
          failCount++;
          AppLogger.warning('Failed to print label: ${label.labelText}');
        }

        // Small delay between prints
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        failCount++;
        AppLogger.error('Error printing label ${label.labelText}', e);
      }
    }

    if (mounted) {
      if (successCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failCount > 0
                  ? '$successCount of ${labelsAsync.length} labels printed ($failCount failed)'
                  : 'All $successCount labels sent to printer',
            ),
            backgroundColor: failCount > 0
                ? Colors.orange
                : SaturdayColors.success,
          ),
        );
      } else {
        _showError('Failed to print all labels');
      }
    }
  } catch (error, stackTrace) {
    AppLogger.error('Error printing step labels', error, stackTrace);
    _showError('Failed to print labels: $error');
  } finally {
    if (mounted) {
      setState(() {
        _isPrinting = false;
      });
    }
  }
}
```

**B. Update Button Condition**
```dart
// Check if step has labels (async)
final labelsAsync = ref.watch(stepLabelsProvider(widget.step.id));

// In the UI
if (labelsAsync.when(
  data: (labels) => labels.isNotEmpty,
  loading: () => false,
  error: (_, __) => false,
) && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) ...[
  OutlinedButton.icon(
    onPressed: (_isSubmitting || _isPrinting) ? null : _printAllStepLabels,
    icon: _isPrinting
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.print),
    label: Text(_isPrinting ? 'Printing...' : 'Print Labels (${labelsAsync.value?.length ?? 0})'),
    style: OutlinedButton.styleFrom(
      foregroundColor: SaturdayColors.primaryDark,
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 12,
      ),
    ),
  ),
  const SizedBox(height: 16),
],
```

---

## Usage Examples

### Example 1: CNC Machining with Multiple Parts

**Configuration**:
```
Step: CNC Machine Sides
Labels:
  1. LEFT SIDE
  2. RIGHT SIDE
```

**Result**: When completing this step, 2 labels are printed, each with the same QR code but different text.

### Example 2: Assembly with Multiple Components

**Configuration**:
```
Step: Assemble Components
Labels:
  1. BASE PLATE - Handle with care
  2. TOP PLATE - Handle with care
  3. SIDE PANEL LEFT
  4. SIDE PANEL RIGHT
```

**Result**: 4 labels printed in sequence.

### Example 3: No Labels

**Configuration**:
```
Step: Quality Inspection
Labels: (none)
```

**Result**: No print button shown, step completes normally.

---

## Migration Path

### For Existing Installations:

1. **Run Migration**: Execute `009_production_step_labels.sql`
2. **Deploy Code**: Update app with new models/UI
3. **Configure Steps**: Admin users add labels to steps that need them
4. **Test**: Complete steps and verify labels print correctly

### No Data Loss:
- Old `generateLabel` and `labelText` fields are not in the migration
- Fresh installation only
- Existing installations won't have these fields

---

## Testing Checklist

- [ ] Run database migration successfully
- [ ] Create step with no labels - no print button shown
- [ ] Create step with 1 label - prints correctly
- [ ] Create step with multiple labels - all print in order
- [ ] Edit step to add labels - saves correctly
- [ ] Edit step to remove labels - deletes correctly
- [ ] Delete step - labels cascade delete
- [ ] Complete step with labels - print button appears
- [ ] Print labels - all labels print with correct text
- [ ] Verify QR codes scan correctly on all labels

---

## Next Steps

1. Implement production step form screen changes
2. Implement complete step screen changes
3. Test end-to-end workflow
4. Update main documentation

---

**Status**: Implementation guide complete
**Date**: 2025-10-11
