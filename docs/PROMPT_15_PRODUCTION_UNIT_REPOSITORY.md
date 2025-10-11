# Prompt 15: Production Unit Repository and Providers - Implementation Summary

## Overview
Implemented the data access layer and state management for production units, including the complete unit creation workflow with QR code generation.

## Implementation Date
2025-10-09

## Files Created

### Repository
- **lib/repositories/production_unit_repository.dart**
  - Complete production unit repository with full CRUD operations
  - Orchestrates complex unit creation workflow
  - Transaction-based operations for data integrity

### Providers
- **lib/providers/production_unit_provider.dart**
  - Riverpod providers for production unit state management
  - Family providers for specific unit lookups
  - Management class for unit operations with automatic cache invalidation

### Models (Basic)
- **lib/models/order.dart**
  - Minimal Order model for future Shopify integration (Prompt 27)
  - Properties: id, shopifyOrderId, shopifyOrderNumber, customerId, orderDate, status

- **lib/models/customer.dart**
  - Minimal Customer model for future Shopify integration (Prompt 27)
  - Properties: id, shopifyCustomerId, email, firstName, lastName
  - Helper: `fullName` getter

## Key Features

### Production Unit Creation Workflow

The `createProductionUnit()` method orchestrates a complex 7-step process:

```dart
Future<ProductionUnit> createProductionUnit({
  required String productId,
  required String variantId,
  required String userId,
  String? shopifyOrderId,
  String? shopifyOrderNumber,
  String? customerName,
}) async
```

**Steps:**
1. **Get Product Code** - Query database for product's product_code
2. **Generate Sequence Number** - Get next sequence for this product
3. **Create Unit ID** - Format as SV-{CODE}-{SEQUENCE}
4. **Generate UUID** - Create unique UUID for QR code
5. **Generate QR Code** - Create QR image with Saturday! logo
6. **Upload to Storage** - Upload QR code to Supabase storage
7. **Insert Record** - Save unit to database with QR URL

**Transaction Safety:**
- All steps must succeed or entire operation fails
- TODO: Implement cleanup for partial failures (e.g., delete uploaded QR if DB insert fails)

### Repository Methods

#### Read Operations
- `getUnitsInProduction()` - All units where is_completed = false
- `getCompletedUnits()` - All units where is_completed = true
- `getUnitByUuid(uuid)` - Lookup by UUID (from QR code scan)
- `getUnitById(id)` - Lookup by database ID
- `getUnitSteps(unitId)` - Production steps for unit's product
- `getUnitStepCompletions(unitId)` - Completed steps for unit
- `searchUnits(query)` - Search by unit ID with ILIKE

#### Write Operations
- `createProductionUnit(...)` - Create new unit with QR generation
- `completeStep(...)` - Mark step complete, auto-complete unit if all done
- `markUnitComplete(unitId)` - Manually mark unit complete
- `updateUnitOwner(unitId, ownerId)` - Assign unit to user
- `deleteUnit(unitId)` - Delete unit and QR code from storage

### Step Completion Logic

When marking a step complete:
1. Create `unit_step_completions` record
2. If first step → set `production_started_at`
3. Count total steps vs completed steps
4. If all complete → automatically call `markUnitComplete()`
5. `markUnitComplete()` sets `is_completed = true` and `production_completed_at`

```dart
Future<ProductionUnit> completeStep({
  required String unitId,
  required String stepId,
  required String userId,
  String? notes,
}) async
```

### Riverpod Providers

#### Data Providers
```dart
// List providers
final unitsInProductionProvider = FutureProvider<List<ProductionUnit>>
final completedUnitsProvider = FutureProvider<List<ProductionUnit>>

// Single unit providers (family)
final unitByUuidProvider = FutureProvider.family<ProductionUnit, String>
final unitByIdProvider = FutureProvider.family<ProductionUnit, String>

// Related data providers (family)
final unitStepsProvider = FutureProvider.family<List<ProductionStep>, String>
final unitStepCompletionsProvider = FutureProvider.family<List<UnitStepCompletion>, String>
```

#### Management Provider
```dart
final productionUnitManagementProvider = Provider<ProductionUnitManagement>

// Usage:
final management = ref.read(productionUnitManagementProvider);
final unit = await management.createUnit(...);
```

**Auto Cache Invalidation:**
- After creating unit → invalidates `unitsInProductionProvider`
- After completing step → invalidates unit, completions, and in-production list
- After marking complete → invalidates both in-production and completed lists
- Ensures UI always shows fresh data

### Production Unit Creation Flow

```dart
// 1. User selects product and variant in UI
final productId = '...';
final variantId = '...';
final userId = currentUser.id;

// 2. Call management provider
final management = ref.read(productionUnitManagementProvider);
final unit = await management.createUnit(
  productId: productId,
  variantId: variantId,
  userId: userId,
  shopifyOrderId: 'optional-order-id',
  shopifyOrderNumber: '#1001',
  customerName: 'John Doe',
);

// 3. Unit is created with:
// - Unique UUID (for QR scanning)
// - Human-readable unit ID (SV-TURNTABLE-00023)
// - QR code image uploaded to storage
// - Database record with all metadata
```

### QR Code Deletion

When deleting a unit, the repository:
1. Fetches unit to get QR code URL
2. Deletes unit from database (cascades to step completions)
3. Parses QR URL to extract bucket and file path
4. Deletes QR image from Supabase storage
5. Continues even if storage deletion fails (logs warning)

## Data Flow Diagrams

### Create Unit Flow
```
UI (Form)
  → ProductionUnitManagement.createUnit()
    → ProductionUnitRepository.createProductionUnit()
      1. Query product_code from products table
      2. IDGenerator.getNextSequenceNumber(productCode)
      3. IDGenerator.generateUnitId(code, seq)
      4. Generate UUID
      5. QRService.generateQRCode(uuid) → Uint8List
      6. StorageService.uploadQRCode(data, uuid) → URL
      7. Insert into production_units table
    ← ProductionUnit
  ← ProductionUnit
← Display confirmation with QR code
```

### Complete Step Flow
```
UI (Step List)
  → ProductionUnitManagement.completeStep()
    → ProductionUnitRepository.completeStep()
      1. Insert into unit_step_completions
      2. Check if first step → set production_started_at
      3. Count total steps
      4. Count completed steps
      5. If all complete → markUnitComplete()
         - Set is_completed = true
         - Set production_completed_at = now
      6. Return updated unit
    ← ProductionUnit
  ← Invalidate providers → UI refreshes
```

## Testing Recommendations

### Unit Tests
- [ ] ProductionUnitRepository.createProductionUnit() with valid data
- [ ] ProductionUnitRepository.createProductionUnit() with invalid product ID
- [ ] ProductionUnitRepository.completeStep() marks step complete
- [ ] ProductionUnitRepository.completeStep() auto-completes unit when all done
- [ ] ProductionUnitRepository.getUnitByUuid() finds correct unit
- [ ] ProductionUnitRepository.searchUnits() filters correctly
- [ ] Order and Customer model serialization

### Integration Tests
- [ ] Create unit → verify QR code uploaded to storage
- [ ] Create unit → verify database record created
- [ ] Complete all steps → verify unit marked complete
- [ ] Delete unit → verify QR code deleted from storage
- [ ] Transaction rollback on failure (mock storage upload failure)

### Manual Testing
- [ ] Create production unit for a product
- [ ] Verify QR code appears in qr-codes bucket
- [ ] Verify unit ID follows SV-{CODE}-{SEQ} format
- [ ] Complete step → verify production_started_at set
- [ ] Complete all steps → verify unit marked complete
- [ ] Delete unit → verify QR code removed from storage
- [ ] Search for units by unit ID

## Known Limitations

1. **No Transaction Rollback**: If QR upload succeeds but database insert fails, QR code remains in storage (TODO added)
2. **Sequential ID Generation**: Race condition possible if two units created simultaneously for same product
3. **No Batch Operations**: Can only create one unit at a time
4. **Limited Search**: Only searches unit_id field, not customer name or order number

## Future Enhancements

1. **Transaction Rollback**
   - Implement cleanup in catch block
   - Delete uploaded QR if database insert fails
   - Use Supabase transactions when available

2. **Batch Unit Creation**
   - Create multiple units at once
   - Optimize QR generation and upload
   - Useful for inventory builds

3. **Advanced Search**
   - Search by customer name
   - Search by order number
   - Filter by product/variant
   - Date range filters

4. **Unit History**
   - Track all changes to unit
   - Audit log for who touched unit when
   - Step completion history with timestamps

5. **Performance Optimization**
   - Cache product codes to avoid repeated queries
   - Batch QR uploads for multiple units
   - Optimize step completion queries

## Related Prompts
- **Prompt 14**: Production Unit Models and QR Code Generation - Foundation models
- **Prompt 16**: Create Production Unit Flow - UI for creating units
- **Prompt 17**: Production Unit List and Detail Screens - UI for viewing units
- **Prompt 18**: QR Code Scanning - Scanning QR codes to look up units
- **Prompt 19**: Production Step Completion - UI for completing steps
- **Prompt 27**: Shopify Order Sync - Full order integration

## Dependencies
- uuid: ^4.2.0 (for UUID generation)
- flutter_riverpod: ^2.6.1 (state management)
- All dependencies from Prompt 14 (QR service, storage service, models)

## Notes
- Repository methods are designed to be called from Riverpod providers, not directly from UI
- All operations log to AppLogger for debugging
- Provider invalidation ensures UI stays in sync with database
- Order and Customer models are minimal placeholders for Prompt 27
- QR code storage is in private bucket, requires signed URLs for access
