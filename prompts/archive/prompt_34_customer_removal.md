# Prompt 34: Remove Customer Data Dependencies

**Context:** Due to Shopify API limitations on the Basic plan (customer PII data is not accessible), the application needs to be refactored to remove all dependencies on customer data. Customer information cannot be synced or stored in the database. This prompt outlines a comprehensive plan to remove all customer-related code while maintaining order tracking functionality.

**Background:** Customer data was initially integrated in Prompt 15 (Order/Customer models), Prompt 16 (Create Unit Flow), Prompt 17 (Unit Display), Prompt 20 (Label Printing), and Prompt 27 (Shopify Order Sync). However, the Shopify Admin API on Basic plans returns the error: "This app is not approved to access the Customer object. Access to personally identifiable information (PII) like customer names, addresses, emails, phone numbers is only available on Shopify, Advanced, and Plus plans."

---

## Affected Files and Components

### Models
1. **lib/models/customer.dart** - Complete removal
2. **lib/models/order.dart** - Remove customer property and references
3. **lib/models/production_unit.dart** - Keep customerName field but document it's derived from order name, not customer

### Repositories
4. **lib/repositories/order_repository.dart** - Remove _upsertCustomer() method and all customer sync logic
5. **lib/repositories/production_unit_repository.dart** - Update to not expect customer data

### Services
6. **lib/services/shopify_queries.dart** - Already updated (customer fields removed from queries)
7. **lib/services/printer_service.dart** - Update label generation to handle missing customer data

### UI Widgets
8. **lib/widgets/production/order_card.dart** - Remove customer email display
9. **lib/widgets/production/unit_card.dart** - Update to show order number instead of customer name
10. **lib/widgets/production/label_layout.dart** - Simplify label to not include customer name
11. **lib/screens/production/create_unit_screen.dart** - Remove customer name from order selection UI
12. **lib/screens/production/unit_detail_screen.dart** - Remove customer information section

### Database
13. **supabase/migrations/008_orders_and_customers.sql** - Create new migration to drop customers table and remove foreign keys

### Tests
14. All test files referencing Customer model or customer data

---

## Implementation Steps

### Step 1: Create Database Migration (009_remove_customers.sql)

Create a new migration that:
- Drops the customers table
- Removes customer_id foreign key from orders table
- Removes any customer-related indexes
- Makes this idempotent (safe to run multiple times)

```sql
-- Migration 009: Remove Customer Data
-- Created: 2025-10-10
-- Description: Remove customers table and all customer references due to Shopify Basic plan limitations

-- Drop foreign key constraint from orders
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'orders_customer_id_fkey'
    AND table_name = 'orders'
  ) THEN
    ALTER TABLE orders DROP CONSTRAINT orders_customer_id_fkey;
  END IF;
END $$;

-- Drop customer_id column from orders if it exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='orders' AND column_name='customer_id'
  ) THEN
    ALTER TABLE orders DROP COLUMN customer_id;
  END IF;
END $$;

-- Drop customers table if it exists
DROP TABLE IF EXISTS customers CASCADE;

-- Drop any remaining customer-related indexes
DROP INDEX IF EXISTS idx_customers_shopify_id;
DROP INDEX IF EXISTS idx_customers_email;
DROP INDEX IF EXISTS idx_orders_customer_id;
```

### Step 2: Remove Customer Model

Delete the entire file:
- `lib/models/customer.dart`

### Step 3: Update Order Model (lib/models/order.dart)

Remove the customer-related code:

**Changes:**
1. Remove `final Customer? customer;` property
2. Remove `this.customerId` from constructor
3. Remove `this.customer` from constructor
4. Update `customerName` getter to return a sensible default (e.g., order number or "Customer Order")
5. Remove customer from `fromJson` factory
6. Remove customer from `fromShopify` factory (already done)
7. Remove customer from `toJson` method
8. Remove customer from `copyWith` method
9. Remove customer from `props` getter
10. Remove `import 'customer.dart';` statement

**New customerName getter:**
```dart
/// Get customer name or order identifier
/// Note: Customer data is not available on Shopify Basic plans
String get customerName {
  return 'Order $shopifyOrderNumber';
}
```

### Step 4: Update ProductionUnit Model (lib/models/production_unit.dart)

**Changes:**
- Keep the `customerName` field but update its documentation
- Update comment to clarify this is derived from order name, not customer PII

```dart
final String? customerName; // Order identifier (not customer PII)
```

### Step 5: Update Order Repository (lib/repositories/order_repository.dart)

**Changes:**
1. Remove the entire `_upsertCustomer()` method (lines 68-102)
2. Remove customer sync logic from `syncOrdersFromShopify()` (lines 35-42)
3. Update `_upsertOrder()` to not accept customerId parameter
4. Remove customer joins from all queries:
   - `getUnfulfilledOrders()` - remove `customer:customers(*)` from select
   - `getOrdersForProductVariant()` - remove `customer:customers(*)` from select
   - `getOrderById()` - remove `customer:customers(*)` from select
   - `getAllOrders()` - remove `customer:customers(*)` from select
5. Remove `import 'package:saturday_app/models/customer.dart';` statement

**Updated _upsertOrder signature:**
```dart
Future<String> _upsertOrder(Order order) async {
  try {
    // Check if order already exists by Shopify ID
    final existing = await _supabase
        .from('orders')
        .select('id')
        .eq('shopify_order_id', order.shopifyOrderId)
        .maybeSingle();

    if (existing != null) {
      // Order exists, update if needed
      final orderId = existing['id'] as String;
      await _supabase.from('orders').update({
        'shopify_order_number': order.shopifyOrderNumber,
        'order_date': order.orderDate.toIso8601String(),
        'status': order.status,
        'fulfillment_status': order.fulfillmentStatus,
        'financial_status': order.financialStatus,
        'tags': order.tags,
        'total_price': order.totalPrice,
      }).eq('id', orderId);

      return orderId;
    } else {
      // Insert new order
      final result = await _supabase.from('orders').insert({
        'shopify_order_id': order.shopifyOrderId,
        'shopify_order_number': order.shopifyOrderNumber,
        'order_date': order.orderDate.toIso8601String(),
        'status': order.status,
        'fulfillment_status': order.fulfillmentStatus,
        'financial_status': order.financialStatus,
        'tags': order.tags,
        'total_price': order.totalPrice,
      }).select('id').single();

      return result['id'] as String;
    }
  } catch (error, stackTrace) {
    AppLogger.error('Failed to upsert order', error, stackTrace);
    rethrow;
  }
}
```

**Updated syncOrdersFromShopify:**
```dart
for (final shopifyOrderData in shopifyOrders) {
  try {
    final order = Order.fromShopify(shopifyOrderData);

    // Upsert order to database (no customer sync on Basic plan)
    final orderId = await _upsertOrder(order);
    await _syncLineItems(orderId, order.lineItems);
    syncedCount++;
  } catch (e) {
    AppLogger.error('Error syncing order ${shopifyOrderData['name']}', e);
  }
}
```

### Step 6: Update Order Card Widget (lib/widgets/production/order_card.dart)

**Changes:**
1. Remove the email display section (lines 87-105)
2. Update customer name display to show order identifier instead

**Replace lines 68-85:**
```dart
// Order info
Row(
  children: [
    const Icon(
      Icons.receipt_outlined,
      size: 18,
      color: SaturdayColors.primaryDark,
    ),
    const SizedBox(width: 8),
    Expanded(
      child: Text(
        order.customerName, // Will show "Order #1001"
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    ),
  ],
),
```

**Remove the entire email block (lines 87-105)**

### Step 7: Update Unit Card Widget (lib/widgets/production/unit_card.dart)

**Changes:**
- Update the customer metadata section to show order number instead
- Change "Customer" label to "Order"

**Replace lines 122-128:**
```dart
if (unit.shopifyOrderNumber != null)
  _buildMetadata(
    context,
    Icons.receipt_outline,
    'Order',
    '#${unit.shopifyOrderNumber}',
  ),
```

### Step 8: Update Printer Service (lib/services/printer_service.dart)

**Changes:**
- Update label generation to handle customerName as order identifier
- Update comments to reflect this is not customer PII

**Update comments on lines 99 and 166-174:**
```dart
/// Generate QR label for a production unit
///
/// Creates a thermal label (default 1" x 1") with:
/// - QR code with embedded logo
/// - Unit ID
/// - Product name + variant
/// - Order number (if applicable)
///
/// Label size can be customized via settings or parameters

// ...

// Order number (if available)
if (unit.shopifyOrderNumber != null)
  pw.Text(
    'Order #${unit.shopifyOrderNumber}',
    style: const pw.TextStyle(fontSize: 3),
    textAlign: pw.TextAlign.center,
  ),
```

**Remove customerName reference on lines 167-174**

### Step 9: Update Label Layout Widget (lib/widgets/qr_labels/label_layout.dart)

Check this file and remove any customer name displays. Replace with order number if needed.

### Step 10: Update Create Unit Screen (lib/screens/production/create_unit_screen.dart)

**Changes:**
- Update order display to show order number prominently instead of customer name
- Remove any customer email or name displays
- Update comments

### Step 11: Update Unit Detail Screen (lib/screens/production/unit_detail_screen.dart)

**Changes:**
- Remove customer information section
- Show order number instead
- Update to display "Order #1001" instead of customer name

### Step 12: Update Production Unit Repository (lib/repositories/production_unit_repository.dart)

**Changes:**
- Update createProductionUnit to accept shopifyOrderNumber instead of customerName
- Update comments to reflect that customerName is derived from order

**Update createProductionUnit method signature (around line 33):**
```dart
Future<ProductionUnit> createProductionUnit({
  required String productId,
  required String variantId,
  required String userId,
  String? shopifyOrderId,
  String? shopifyOrderNumber,
  String? orderId, // Internal order ID to link to this unit
}) async {
  try {
    AppLogger.info('Creating production unit for product: $productId');

    // ... existing code ...

    // Step 7: Insert unit record to database
    AppLogger.info('Creating unit record in database...');
    final unitData = {
      'uuid': uuid,
      'unit_id': unitId,
      'product_id': productId,
      'variant_id': variantId,
      'shopify_order_id': shopifyOrderId,
      'shopify_order_number': shopifyOrderNumber,
      'customer_name': shopifyOrderNumber != null ? 'Order #$shopifyOrderNumber' : null,
      'qr_code_url': qrCodeUrl,
      'is_completed': false,
      'created_by': userId,
    };

    // ... rest of method ...
```

### Step 13: Update Production Unit Provider (lib/providers/production_unit_provider.dart)

**Changes:**
- Update createUnit method to not pass customerName

**Update around lines 60-77:**
```dart
Future<ProductionUnit> createUnit({
  required String productId,
  required String variantId,
  required String userId,
  String? shopifyOrderId,
  String? shopifyOrderNumber,
  String? orderId,
}) async {
  final repository = ref.read(productionUnitRepositoryProvider);
  final unit = await repository.createProductionUnit(
    productId: productId,
    variantId: variantId,
    userId: userId,
    shopifyOrderId: shopifyOrderId,
    shopifyOrderNumber: shopifyOrderNumber,
    orderId: orderId,
  );

  // Invalidate providers to refresh data
  ref.invalidate(unitsInProductionProvider);

  return unit;
}
```

### Step 14: Update Database Migration File

Update `supabase/migrations/008_orders_and_customers.sql` to remove customers table entirely, OR create a new migration 009_remove_customers.sql (recommended).

**Recommended approach:** Create new migration `supabase/migrations/009_remove_customers.sql` with the SQL from Step 1.

### Step 15: Remove Customer-Related Tests

Delete or update test files:
1. Remove `test/models/customer_test.dart` entirely
2. Update `test/models/order_test.dart` - remove customer-related tests
3. Update `test/repositories/order_repository_test.dart` - remove customer sync tests
4. Update any widget tests that reference customer data

### Step 16: Update Documentation

Update the following documentation files to remove customer data references:

**In prompt_plan.md:**
- Update Prompt 15 description to note customer model is no longer used
- Update Prompt 16 to note customer association is not available
- Update Prompt 17 to note customer display is removed
- Update Prompt 20 to note labels don't show customer names
- Update Prompt 27 to note customer sync is skipped

---

## Testing Plan

### Unit Tests
1. Test Order model without customer property
2. Test Order.customerName getter returns order number
3. Test order repository methods don't reference customer data
4. Test production unit creation without customer name

### Integration Tests
1. Test order sync from Shopify (without customer data)
2. Test creating production unit with order (shows order number, not customer)
3. Test label generation (no customer name)

### Manual Testing
1. Sync orders from Shopify - verify no customer sync attempted
2. Create production unit linked to order - verify order number displayed
3. View unit detail - verify no customer information shown, only order number
4. Print label - verify label shows order number, not customer name
5. View order card - verify displays order number, no customer email

---

## Migration Strategy

### For Fresh Installations
- Simply don't run migration 008, or run 009 immediately after

### For Existing Installations
1. Run migration 009_remove_customers.sql to drop customers table
2. Deploy updated application code
3. Verify no errors in logs
4. Re-sync orders to ensure they work without customer data

---

## Rollback Plan

If issues arise:
1. Revert to previous git commit before Prompt 34
2. Customers table will still exist (migration 009 can be rolled back)
3. Previous code still has customer references intact

---

## Success Criteria

- [ ] Customer model file deleted
- [ ] Order model no longer references Customer
- [ ] All repositories updated to not sync customer data
- [ ] All UI updated to show order numbers instead of customer names
- [ ] Database migration created and tested
- [ ] All tests passing
- [ ] Manual testing complete
- [ ] Order sync works without customer data
- [ ] Labels print successfully without customer names
- [ ] No errors in application logs related to customer data

---

## Notes

- The `customerName` field in ProductionUnit is kept for backward compatibility but now stores "Order #1001" format instead of actual customer names
- Order numbers provide sufficient identification for production tracking
- This change aligns with Shopify Basic plan limitations
- Future upgrade to Shopify Plus/Advanced could re-introduce customer data if needed

---

**Prompt Number:** 34
**Dependencies:** Prompts 15, 16, 17, 20, 27
**Estimated Time:** 4-6 hours
**Complexity:** Medium
**Testing Required:** Unit, Integration, Manual
