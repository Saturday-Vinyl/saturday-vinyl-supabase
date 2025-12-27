# Label Printing Feature Documentation

## Overview

The Saturday! Admin App includes a comprehensive label printing system designed for thermal printers (1" x 1" labels). This system supports printing labels at two key points in the production workflow:

1. **Unit Creation Labels** - Generated when a production unit is first created
2. **Step-Specific Labels** - Generated during production when completing specific steps

This document focuses on the step-specific label printing feature, which **supports multiple labels per production step**. For example, a "CNC Machine Sides" step can generate two separate labels: one for "LEFT SIDE" and one for "RIGHT SIDE".

---

## Feature Components

### 1. Database Schema

**Migration**: `009_production_step_labels.sql`

A new `step_labels` table has been created with a **one-to-many relationship** to production steps:

```sql
CREATE TABLE public.step_labels (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  step_id UUID NOT NULL REFERENCES public.production_steps(id) ON DELETE CASCADE,
  label_text TEXT NOT NULL,
  label_order INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT positive_label_order CHECK (label_order > 0)
);
```

**Key Design Decisions:**
- **Separate table** (not JSON array or embedded fields) for proper relational design
- **Cascade delete** - When a production step is deleted, all its labels are automatically deleted
- **Label order** - Controls the sequence in which labels are printed
- **Mandatory label text** - Each label must have text (no empty labels)

**Indexes:**
```sql
CREATE INDEX idx_step_labels_step_id ON public.step_labels(step_id);
CREATE INDEX idx_step_labels_order ON public.step_labels(step_id, label_order);
```

---

### 2. Data Model

**File**: `lib/models/step_label.dart`

New `StepLabel` model for individual labels:

```dart
class StepLabel extends Equatable {
  final String id;           // UUID
  final String stepId;       // Foreign key to ProductionStep
  final String labelText;    // e.g., "LEFT SIDE", "RIGHT SIDE"
  final int labelOrder;      // Print order (1, 2, 3...)
  final DateTime createdAt;
  final DateTime updatedAt;

  // Methods: fromJson, toJson, copyWith, toString
}
```

**File**: `lib/models/production_step.dart`

The `ProductionStep` model remains unchanged - label configuration is now stored in the separate `step_labels` table.

---

### 3. Repository Layer

**File**: `lib/repositories/step_label_repository.dart`

Handles all database operations for step labels:

```dart
class StepLabelRepository {
  // Fetch all labels for a step (ordered by label_order)
  Future<List<StepLabel>> getLabelsForStep(String stepId);

  // Create multiple labels in a single batch transaction
  Future<List<StepLabel>> batchCreateLabels(String stepId, List<String> labelTexts);

  // Update labels for a step (delete old, create new)
  Future<List<StepLabel>> updateLabelsForStep(String stepId, List<String> labelTexts);

  // Delete all labels for a step
  Future<void> deleteLabelsForStep(String stepId);
}
```

**Key Features:**
- Batch operations for efficiency
- Automatic ordering (1, 2, 3...)
- Transaction safety for updates
- CASCADE delete on step deletion

---

### 4. State Management

**File**: `lib/providers/step_label_provider.dart`

Riverpod providers for reactive label management:

```dart
// Repository instance provider
final stepLabelRepositoryProvider = Provider<StepLabelRepository>((ref) {
  return StepLabelRepository(ref.read(supabaseClientProvider));
});

// Labels for a specific step (family provider)
final stepLabelsProvider = FutureProvider.family<List<StepLabel>, String>(
  (ref, stepId) async {
    final repository = ref.read(stepLabelRepositoryProvider);
    return repository.getLabelsForStep(stepId);
  },
);
```

**Usage Pattern:**
```dart
// Watch labels reactively
final labelsAsync = ref.watch(stepLabelsProvider(stepId));

labelsAsync.when(
  data: (labels) => /* show labels */,
  loading: () => /* show spinner */,
  error: (error, stack) => /* show error */,
);
```

---

### 5. Step Configuration UI

**File**: `lib/screens/products/production_step_form_screen.dart`

**Complete rewrite** to support dynamic label list management.

#### UI Features

1. **Label List Section**
   - Header: "Step Labels" with description
   - Dynamic list of label text fields
   - Numbered badges (1, 2, 3...) for each label
   - Add button: "Add Another Label"
   - Delete button for each label (if more than 1)

2. **Label Text Fields**
   - Placeholder: "e.g., LEFT SIDE"
   - Max length: 100 characters
   - Validation: At least one non-empty label required

3. **Controller Management**
   ```dart
   List<TextEditingController> _labelControllers = [];

   @override
   void dispose() {
     // Proper cleanup to prevent memory leaks
     for (var controller in _labelControllers) {
       controller.dispose();
     }
     super.dispose();
   }
   ```

4. **Async Label Loading**
   ```dart
   Future<void> _loadExistingLabels() async {
     final labels = await ref.read(stepLabelsProvider(widget.step!.id).future);

     // Create controllers for existing labels
     for (final label in labels) {
       _labelControllers.add(TextEditingController(text: label.labelText));
     }

     // Ensure at least one empty controller
     if (_labelControllers.isEmpty) {
       _labelControllers.add(TextEditingController());
     }
   }
   ```

5. **Save Logic**
   ```dart
   // Extract non-empty label texts
   final labelTexts = _labelControllers
     .map((c) => c.text.trim())
     .where((t) => t.isNotEmpty)
     .toList();

   if (labelTexts.isEmpty) {
     // Show error - at least one label required
     return;
   }

   // Batch update all labels for this step
   await labelManagement.updateLabelsForStep(widget.step!.id, labelTexts);
   ```

---

### 6. Label Generation Service

**File**: `lib/services/printer_service.dart`

#### Method: `generateStepLabel()`

```dart
Future<Uint8List> generateStepLabel({
  required ProductionUnit unit,
  required String productName,
  required String variantName,
  required Uint8List qrImageData,      // QR generated once, reused for all labels
  String? labelText,                    // Custom text from StepLabel
  double? labelWidth,                   // Optional override (default: 1.0")
  double? labelHeight,                  // Optional override (default: 1.0")
}) async
```

**Label Layout** (top to bottom):
1. **QR Code** - 50x50 points, centered, branded with Saturday logo
2. **Unit ID** - Bold, 6pt font (e.g., "SV-TURNTABLE-00001")
3. **Product + Variant** - 4pt font (e.g., "Turntable - Standard")
4. **Label Text** - **Bold, 5pt font** (e.g., "LEFT SIDE", "RIGHT SIDE", "FRAGILE")
5. **Order Number** - 3pt font (if unit is part of an order)

**Key Features:**
- Default label size: 1" x 1" (72 x 72 points)
- High contrast for thermal printing
- Text truncation with overflow handling
- Custom label text shown prominently in bold

---

### 7. Step Completion UI

**File**: `lib/screens/production/complete_step_screen.dart`

**Complete rewrite** to support printing multiple labels sequentially.

#### Print Labels Button

**Dynamic Button Display** using Consumer widget:

```dart
Consumer(
  builder: (context, ref, child) {
    final labelsAsync = ref.watch(stepLabelsProvider(widget.step.id));

    return labelsAsync.when(
      data: (labels) {
        if (labels.isEmpty) return const SizedBox.shrink();

        return OutlinedButton.icon(
          icon: _isPrintingLabels
            ? SizedBox(/* spinner */)
            : Icon(Icons.print),
          label: Text(_isPrintingLabels
            ? 'Printing...'
            : 'Print Labels (${labels.length})'),
          onPressed: _isPrintingLabels ? null : _printAllStepLabels,
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  },
)
```

**Button Behavior:**
- Shows count: "Print Labels (2)" if 2 labels configured
- Hidden if no labels configured for this step
- Disabled during printing operation
- Desktop platforms only (macOS, Windows, Linux)

#### Sequential Printing Logic

```dart
Future<void> _printAllStepLabels() async {
  setState(() => _isPrintingLabels = true);

  try {
    // 1. Fetch all labels for this step
    final labels = await ref.read(stepLabelsProvider(widget.step.id).future);

    if (labels.isEmpty) {
      _showError('No labels configured for this step');
      return;
    }

    // 2. Fetch unit, product, variant data
    final unit = await _fetchUnit();
    final product = await _fetchProduct(unit.productId);
    final variant = await _fetchVariant(unit.variantId);

    // 3. Generate QR code ONCE (reuse for all labels)
    final qrImageData = await qrService.generateQRCode(
      unit.uuid,
      size: 512,
      embedLogo: true,
    );

    // 4. Print each label sequentially with delay
    int successCount = 0;
    int failCount = 0;

    for (final label in labels) {
      // Generate label with specific text
      final labelData = await printerService.generateStepLabel(
        unit: unit,
        productName: product.name,
        variantName: variant.name,
        qrImageData: qrImageData,
        labelText: label.labelText,  // "LEFT SIDE", "RIGHT SIDE", etc.
      );

      // Send to printer
      final success = await printerService.printQRLabel(labelData);
      if (success) {
        successCount++;
      } else {
        failCount++;
      }

      // 500ms delay between labels
      if (label != labels.last) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    // 5. Show summary message
    if (failCount == 0) {
      _showSuccess('All $successCount labels sent to printer successfully');
    } else {
      _showWarning('$successCount of ${labels.length} labels printed ($failCount failed)');
    }

  } catch (e) {
    _showError('Failed to print labels: $e');
  } finally {
    setState(() => _isPrintingLabels = false);
  }
}
```

**Key Features:**
- Single QR code generation (efficient)
- Sequential printing with delays (prevents printer overload)
- Success/failure tracking per label
- User-friendly summary messages
- Proper error handling

---

## User Workflows

### Workflow 1: Configure Multiple Labels for a Step

**For Admin Users with `manage_products` permission:**

1. Navigate to Product Details screen
2. Click "Configure Steps"
3. Click "Add Step" or edit existing step
4. Fill in step name and description
5. Scroll to "Step Labels" section
6. Enter text for first label (e.g., "LEFT SIDE")
7. Click "Add Another Label" button
8. Enter text for second label (e.g., "RIGHT SIDE")
9. Repeat for additional labels as needed
10. Click "Create Step" or "Save Changes"

**Result:**
- Multiple labels associated with the step
- Labels stored with ordering (1, 2, 3...)
- Print button will show count during step completion

**Example Configuration:**

**Step: "CNC Machine Sides"**
- Label 1: "LEFT SIDE"
- Label 2: "RIGHT SIDE"

**Step: "Quality Control"**
- Label 1: "QC PASSED ✓"
- Label 2: "APPROVED FOR ASSEMBLY"
- Label 3: "INSPECTED BY: QC TEAM"

---

### Workflow 2: Print Multiple Labels During Production

**For Production Workers:**

1. Scan QR code or navigate to production unit
2. Click on a production step to complete it
3. Complete Step dialog appears
4. (Optional) Add notes about the step
5. **If step has labels configured:**
   - "Print Labels (2)" button appears above action buttons
   - Click "Print Labels (2)"
   - System prints each label sequentially:
     - Prints "LEFT SIDE" label
     - 500ms delay
     - Prints "RIGHT SIDE" label
   - Success message appears: "All 2 labels sent to printer successfully"
6. Apply physical labels to appropriate parts
7. Click "Complete Step" to finish
8. Step marked complete, unit progresses

**Result:**
- Multiple physical labels printed, each with:
  - Same QR code (for the unit)
  - Same unit ID, product, variant
  - Different label text on each label
  - Order number (if applicable)

---

## Label Content Examples

### Example 1: CNC Machining Step with Two Sides

**Configuration:**
- Product: "Turntable"
- Variant: "Standard"
- Step: "CNC Machine Sides"
- Labels:
  1. "LEFT SIDE"
  2. "RIGHT SIDE"

**Printed Label 1:**
```
┌─────────────┐
│   [QR CODE]  │ ← Saturday branded QR code
│              │
│ SV-TURN-0001 │ ← Unit ID (bold)
│              │
│ Turntable -  │ ← Product + Variant
│   Standard   │
│              │
│  LEFT SIDE   │ ← Custom text (bold, prominent)
└─────────────┘
```

**Printed Label 2:**
```
┌─────────────┐
│   [QR CODE]  │ ← Same QR code
│              │
│ SV-TURN-0001 │ ← Same unit ID
│              │
│ Turntable -  │ ← Same product info
│   Standard   │
│              │
│  RIGHT SIDE  │ ← Different label text
└─────────────┘
```

---

### Example 2: Multi-Stage Quality Control

**Configuration:**
- Product: "Vinyl Player"
- Variant: "Deluxe"
- Step: "Quality Inspection"
- Labels:
  1. "QC PASSED ✓"
  2. "APPROVED FOR ASSEMBLY"
  3. "INSPECTED: 2025-10-11"

**Result:**
3 labels printed sequentially, each with the same QR and unit info, but different status text.

---

### Example 3: Complex Assembly with Multiple Components

**Configuration:**
- Product: "Turntable"
- Variant: "Premium"
- Step: "Assemble Components"
- Labels:
  1. "PLATTER ASSEMBLY"
  2. "TONEARM ASSEMBLY"
  3. "BASE ASSEMBLY"
  4. "MOTOR ASSEMBLY"

**Result:**
4 labels printed for 4 different sub-assemblies, all linked to the same production unit via QR code.

---

## Use Cases

### Use Case 1: Symmetrical Parts Identification

**Scenario:**
A CNC step produces two sides (left and right) that are mirror images. Each needs its own label to prevent assembly errors.

**Configuration:**
- Step: "CNC Machine Sides"
- Labels:
  1. "LEFT SIDE"
  2. "RIGHT SIDE"

**Benefit:**
- Each physical part gets its own label
- Workers can't mix up left/right sides
- Both parts trace back to same production unit via QR

---

### Use Case 2: Multi-Stage Quality Control

**Scenario:**
A QC step requires multiple checks, and each passed check gets its own certification label.

**Configuration:**
- Step: "Quality Inspection"
- Labels:
  1. "ELECTRICAL TEST PASSED"
  2. "MECHANICAL TEST PASSED"
  3. "FINAL QC APPROVED"

**Benefit:**
- Visual proof of each QC stage
- Multiple validation points
- Comprehensive quality documentation

---

### Use Case 3: Sub-Assembly Tracking

**Scenario:**
A complex assembly step produces multiple sub-assemblies that need individual tracking labels.

**Configuration:**
- Step: "Create Sub-Assemblies"
- Labels:
  1. "SUB-ASSEMBLY A"
  2. "SUB-ASSEMBLY B"
  3. "SUB-ASSEMBLY C"

**Benefit:**
- Track individual components through production
- Each sub-assembly scannable back to parent unit
- Improved inventory management

---

### Use Case 4: Special Handling Instructions

**Scenario:**
Different parts in the same step require different handling procedures.

**Configuration:**
- Step: "Precision Assembly"
- Labels:
  1. "FRAGILE - Handle with care"
  2. "TEMPERATURE SENSITIVE - Keep cool"
  3. "ORIENTATION CRITICAL - This side up"

**Benefit:**
- Clear, specific handling instructions
- Reduces damage and errors
- Improves worker awareness

---

## Technical Details

### Label Dimensions

- **Default Size**: 1" x 1" (72 x 72 points at 72 DPI)
- **Customizable**: Via printer settings
- **Format**: PDF (for precise thermal printing)
- **Resolution**: Vector-based (scales perfectly)

### Font Sizes

- **QR Code**: 50 x 50 points (with Saturday logo)
- **Unit ID**: 6pt, bold
- **Product/Variant**: 4pt, regular
- **Label Text**: 5pt, **bold** (for prominence)
- **Order Number**: 3pt, regular

### Printing Behavior

1. **QR Generation**: Once per print job (reused for all labels)
2. **Sequential Printing**: Labels print one at a time with 500ms delay
3. **Direct Print**: No dialog shown, sends to configured printer
4. **Progress Tracking**: Success/failure count per label
5. **Error Handling**: Individual label failures don't stop the batch
6. **User Feedback**: Summary message after all labels printed

### Database Performance

- **Indexed Queries**: Fast lookup by step_id
- **Ordered Results**: Automatic sorting by label_order
- **Cascade Deletes**: Automatic cleanup when step deleted
- **Batch Operations**: Efficient multi-label updates

---

## Configuration Requirements

### Printer Setup

1. **Thermal Printer**:
   - Must be configured in system settings
   - Recommended: Desktop thermal label printer
   - Label size: 1" x 1" or larger

2. **App Settings**:
   - Navigate to Settings screen
   - Select default printer
   - Configure label dimensions (if non-standard)
   - Test print to verify setup

### Permissions

- **Step Configuration**: Requires `manage_products` permission
- **Label Printing**: Available to all authenticated production workers
- **Printer Access**: Desktop platforms only (macOS, Windows, Linux)

---

## Best Practices

### For Administrators

1. **Plan Label Count**
   - Consider how many physical parts the step produces
   - Each part needing identification should get its own label
   - Avoid redundant labels

2. **Use Clear, Distinctive Text**
   - Make each label text unique and descriptive
   - Use ALL CAPS for visibility
   - Keep text concise (1-2 lines max)
   - Examples: "LEFT SIDE" vs "RIGHT SIDE", not "SIDE 1" vs "SIDE 2"

3. **Logical Ordering**
   - Labels print in the order configured
   - Order should match physical workflow
   - Example: "FRONT PANEL" (1), "BACK PANEL" (2), "SIDE PANELS" (3)

4. **Test Before Production**
   - Create test step with multiple labels
   - Print test labels to verify:
     - All labels print successfully
     - Text is readable
     - QR codes scan correctly
     - Timing between labels is appropriate

### For Production Workers

1. **Print All Labels at Once**
   - Click "Print Labels" button once
   - Wait for all labels to print
   - Don't interrupt the printing sequence

2. **Apply Labels Immediately**
   - Match label text to physical part
   - Apply to clean, flat surface
   - Ensure QR code is unobstructed and scannable

3. **Verify Each Label**
   - Scan each QR code to verify
   - Confirm correct label on correct part
   - Report any label quality issues

4. **Track Label Inventory**
   - Monitor label printer supply
   - Replace rolls before running out
   - Keep backup label stock available

---

## Troubleshooting

### Issue: Print Button Shows Wrong Count

**Possible Causes:**
1. Step labels not saved correctly
2. Cache not refreshed
3. Database sync issue

**Solution:**
1. Edit step configuration and verify label count
2. Close and reopen complete step dialog
3. Refresh production unit screen

---

### Issue: Labels Print in Wrong Order

**Possible Causes:**
1. Label order not set correctly in database
2. Race condition in printing loop

**Solution:**
1. Edit step, delete all labels, re-add in correct order
2. Report issue to development team
3. Labels auto-ordered by creation sequence

---

### Issue: Some Labels Don't Print

**Possible Causes:**
1. Printer paper jam or out of paper
2. Printer buffer overflow
3. Network interruption (if network printer)
4. Individual label generation failed

**Solution:**
1. Check printer status and paper supply
2. Reduce printing speed (increase delay)
3. Check network connection
4. Review error message for specific failure
5. Reprint failed labels by clicking button again

---

### Issue: QR Codes Different on Each Label

**Possible Causes:**
This should NOT happen - QR code should be identical on all labels from same print job.

**Solution:**
1. Report as bug - QR generated once and reused
2. Verify all labels scan to same unit
3. Check printer firmware/drivers

---

### Issue: Label Text Truncated

**Possible Causes:**
1. Text too long for label size
2. Font size too large
3. Label layout issue

**Solution:**
1. Shorten label text in step configuration
2. Use abbreviations (e.g., "L SIDE" instead of "LEFT SIDE")
3. Keep text under 20 characters for best results

---

## Future Enhancements

### Potential Improvements

1. **Label Preview**
   - Show preview of all labels before printing
   - Verify text fits and looks correct
   - Adjust layout per label

2. **Conditional Labels**
   - Print different labels based on variant
   - Dynamic label count per unit configuration
   - Template variables in label text

3. **Label Templates**
   - Multiple label layouts
   - Customizable designs per product
   - Color label support

4. **Reprint Individual Labels**
   - Reprint specific label from history
   - Track which labels were reprinted
   - Damage/lost label replacement

5. **Advanced Formatting**
   - Rich text formatting
   - Icons and symbols per label
   - Variable font sizes per label

6. **Batch Printing**
   - Print labels for multiple units at once
   - Queue printing jobs
   - Scheduled printing

7. **Mobile Support**
   - Bluetooth label printers
   - Mobile app label printing
   - Cloud print integration

8. **Analytics**
   - Label usage statistics per step
   - Reprint frequency tracking
   - Quality metrics per label type

---

## Related Documentation

- [Multiple Labels Implementation Guide](MULTIPLE_LABELS_IMPLEMENTATION_GUIDE.md)
- [Prompt 14: Production Units and QR Code Generation](PROMPT_14_PRODUCTION_UNITS_QR.md)
- [Production Steps Configuration Guide](../prompt_plan.md#prompt-12-production-step-configuration)

---

## Database Migration

To enable this feature in an existing installation:

```bash
# Run the migration
psql -d your_database -f supabase/migrations/009_production_step_labels.sql

# Or in Supabase dashboard:
# 1. Go to SQL Editor
# 2. Paste contents of 009_production_step_labels.sql
# 3. Run migration
# 4. Verify table created: step_labels
```

**Note**: The migration has been fixed to properly handle RLS policies with permission checking via JOIN.

---

## API Reference

### StepLabel Model

```dart
class StepLabel {
  final String id;              // UUID
  final String stepId;          // FK to ProductionStep
  final String labelText;       // e.g., "LEFT SIDE"
  final int labelOrder;         // 1, 2, 3...
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

### StepLabelRepository Methods

```dart
// Fetch all labels for a step (ordered)
Future<List<StepLabel>> getLabelsForStep(String stepId);

// Create multiple labels in batch
Future<List<StepLabel>> batchCreateLabels(
  String stepId,
  List<String> labelTexts,
);

// Update labels for step (delete old, create new)
Future<List<StepLabel>> updateLabelsForStep(
  String stepId,
  List<String> labelTexts,
);

// Delete all labels for a step
Future<void> deleteLabelsForStep(String stepId);
```

### PrinterService Methods

```dart
// Generate step-specific label
Future<Uint8List> generateStepLabel({
  required ProductionUnit unit,
  required String productName,
  required String variantName,
  required Uint8List qrImageData,
  String? labelText,
  double? labelWidth,
  double? labelHeight,
});

// Print label to configured printer
Future<bool> printQRLabel(Uint8List labelData);
```

### Riverpod Providers

```dart
// Repository provider
final stepLabelRepositoryProvider = Provider<StepLabelRepository>(...);

// Labels for a specific step
final stepLabelsProvider = FutureProvider.family<List<StepLabel>, String>(...);
```

---

## Support

For issues or questions about label printing:

1. Check printer configuration in Settings
2. Verify step has labels configured
3. Review logs for error messages
4. Check network/printer connectivity
5. Contact system administrator

---

**Document Version**: 2.0
**Last Updated**: 2025-10-11
**Author**: Saturday! Development Team
**Major Changes**: Complete rewrite to document multiple labels per step feature
