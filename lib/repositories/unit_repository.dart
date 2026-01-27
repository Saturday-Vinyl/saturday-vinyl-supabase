import 'package:saturday_app/models/unit.dart';
import 'package:saturday_app/models/unit_filter.dart';
import 'package:saturday_app/models/unit_list_item.dart';
import 'package:saturday_app/services/qr_service.dart';
import 'package:saturday_app/services/storage_service.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:saturday_app/utils/id_generator.dart';
import 'package:uuid/uuid.dart';

/// Repository for managing units (unified production + consumer devices)
///
/// This repository replaces ProductionUnitRepository with the new unified
/// Unit model that combines production and consumer device tracking.
class UnitRepository {
  final _supabase = SupabaseService.instance.client;
  final _qrService = QRService();
  final _storageService = StorageService();
  final _uuid = const Uuid();

  // ============================================================================
  // Unit Creation
  // ============================================================================

  /// Create a new unit with QR code
  ///
  /// This method orchestrates the entire unit creation process:
  /// 1. Get product code from product
  /// 2. Generate next sequence number
  /// 3. Create serial number (e.g., "SV-HUB-00001")
  /// 4. Generate UUID for QR code
  /// 5. Generate QR code with logo
  /// 6. Upload QR code to storage
  /// 7. Insert unit record to database with QR URL
  /// 8. If orderId provided, link order to unit
  Future<Unit> createUnit({
    required String productId,
    required String variantId,
    required String userId,
    String? orderId,
  }) async {
    try {
      AppLogger.info('Creating unit for product: $productId');

      // Step 1: Get product code from product
      final productResponse = await _supabase
          .from('products')
          .select('product_code')
          .eq('id', productId)
          .single();

      final productCode = productResponse['product_code'] as String;
      AppLogger.info('Product code: $productCode');

      // Step 2: Generate next sequence number
      final sequenceNumber =
          await IDGenerator.getNextSequenceNumber(productCode);
      AppLogger.info('Sequence number: $sequenceNumber');

      // Step 3: Create serial number
      final serialNumber =
          IDGenerator.generateUnitId(productCode, sequenceNumber);
      AppLogger.info('Serial number: $serialNumber');

      // Step 4: Generate UUID for QR code
      final uuid = _uuid.v4();
      AppLogger.info('UUID: $uuid');

      // Step 5: Generate QR code with logo
      AppLogger.info('Generating QR code...');
      final qrImageData = await _qrService.generateQRCode(uuid);
      AppLogger.info('QR code generated (${qrImageData.length} bytes)');

      // Step 6: Upload QR code to storage
      AppLogger.info('Uploading QR code to storage...');
      final qrCodeUrl = await _storageService.uploadQRCode(qrImageData, uuid);
      AppLogger.info('QR code uploaded: $qrCodeUrl');

      // Step 7: Insert unit record to database
      AppLogger.info('Creating unit record in database...');
      final unitData = {
        'serial_number': serialNumber,
        'product_id': productId,
        'variant_id': variantId,
        'order_id': orderId,
        'qr_code_url': qrCodeUrl,
        'status': UnitStatus.unprovisioned.databaseValue,
        'production_started_at': DateTime.now().toIso8601String(),
        'is_completed': false,
        'created_by': userId,
      };

      final response =
          await _supabase.from('units').insert(unitData).select().single();

      final unit = Unit.fromJson(response);
      AppLogger.info('Unit created successfully: ${unit.serialNumber}');

      // Step 8: Link order to unit if orderId provided
      if (orderId != null) {
        AppLogger.info('Linking order $orderId to unit ${unit.id}');
        try {
          await _supabase
              .from('orders')
              .update({'assigned_unit_id': unit.id}).eq('id', orderId);
          AppLogger.info('Order linked successfully');
        } catch (orderError) {
          AppLogger.warning('Failed to link order to unit: $orderError');
        }
      }

      return unit;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create unit', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Unit Retrieval
  // ============================================================================

  /// Get a unit by its database ID
  Future<Unit> getUnitById(String id) async {
    try {
      AppLogger.info('Fetching unit by ID: $id');

      final response =
          await _supabase.from('units').select().eq('id', id).single();

      final unit = Unit.fromJson(response);
      return unit;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch unit by ID', error, stackTrace);
      rethrow;
    }
  }

  /// Get a unit by its serial number (e.g., "SV-HUB-00001")
  Future<Unit?> getUnitBySerialNumber(String serialNumber) async {
    try {
      AppLogger.info('Fetching unit by serial number: $serialNumber');

      final response = await _supabase
          .from('units')
          .select()
          .eq('serial_number', serialNumber)
          .maybeSingle();

      if (response == null) {
        AppLogger.info('No unit found with serial number: $serialNumber');
        return null;
      }

      final unit = Unit.fromJson(response);
      AppLogger.info('Found unit: ${unit.serialNumber}');
      return unit;
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to fetch unit by serial number', error, stackTrace);
      rethrow;
    }
  }

  /// Get all units in production (started but not completed)
  Future<List<Unit>> getUnitsInProduction() async {
    try {
      AppLogger.info('Fetching units in production');

      final response = await _supabase
          .from('units')
          .select()
          .eq('is_completed', false)
          .not('production_started_at', 'is', null)
          .order('created_at', ascending: false);

      final units =
          (response as List).map((json) => Unit.fromJson(json)).toList();

      AppLogger.info('Found ${units.length} units in production');
      return units;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch units in production', error, stackTrace);
      rethrow;
    }
  }

  /// Get all completed units
  Future<List<Unit>> getCompletedUnits() async {
    try {
      AppLogger.info('Fetching completed units');

      final response = await _supabase
          .from('units')
          .select()
          .eq('is_completed', true)
          .order('production_completed_at', ascending: false);

      final units =
          (response as List).map((json) => Unit.fromJson(json)).toList();

      AppLogger.info('Found ${units.length} completed units');
      return units;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch completed units', error, stackTrace);
      rethrow;
    }
  }

  /// Get units by status
  Future<List<Unit>> getUnitsByStatus(UnitStatus status) async {
    try {
      AppLogger.info('Fetching units with status: ${status.databaseValue}');

      final response = await _supabase
          .from('units')
          .select()
          .eq('status', status.databaseValue)
          .order('created_at', ascending: false);

      final units =
          (response as List).map((json) => Unit.fromJson(json)).toList();

      AppLogger.info('Found ${units.length} units with status $status');
      return units;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch units by status', error, stackTrace);
      rethrow;
    }
  }

  /// Get units for a specific product
  Future<List<Unit>> getUnitsByProduct(String productId) async {
    try {
      AppLogger.info('Fetching units for product: $productId');

      final response = await _supabase
          .from('units')
          .select()
          .eq('product_id', productId)
          .order('created_at', ascending: false);

      final units =
          (response as List).map((json) => Unit.fromJson(json)).toList();

      AppLogger.info('Found ${units.length} units for product $productId');
      return units;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch units by product', error, stackTrace);
      rethrow;
    }
  }

  /// Search units by serial number
  Future<List<Unit>> searchUnits(String query) async {
    try {
      AppLogger.info('Searching units: $query');

      final response = await _supabase
          .from('units')
          .select()
          .ilike('serial_number', '%$query%')
          .order('created_at', ascending: false)
          .limit(50);

      final units =
          (response as List).map((json) => Unit.fromJson(json)).toList();

      AppLogger.info('Found ${units.length} units matching "$query"');
      return units;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to search units', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Dashboard View
  // ============================================================================

  /// Get unit list items for dashboard display
  ///
  /// Fetches from the `units_dashboard` view which joins units with their
  /// primary device for efficient list rendering. Supports filtering and sorting.
  Future<List<UnitListItem>> getUnitListItems({UnitFilter? filter}) async {
    try {
      AppLogger.info('Fetching unit list items with filter: $filter');

      // Build query with filters
      var queryBuilder = _supabase.from('units_dashboard').select();

      // Apply status filter
      if (filter?.status != null) {
        queryBuilder = queryBuilder.eq('status', filter!.status!.databaseValue);
      }

      // Apply connected filter
      if (filter?.isConnected != null) {
        queryBuilder = queryBuilder.eq('is_connected', filter!.isConnected!);
      }

      // Apply search filter (serial_number or device_name)
      if (filter?.searchQuery?.isNotEmpty == true) {
        final searchTerm = filter!.searchQuery!;
        queryBuilder = queryBuilder.or(
          'serial_number.ilike.%$searchTerm%,device_name.ilike.%$searchTerm%',
        );
      }

      // Apply sorting and execute
      final sortColumn = filter?.sortBy.columnName ?? 'created_at';
      final ascending = filter?.sortAscending ?? false;
      final response = await queryBuilder.order(sortColumn, ascending: ascending);

      final items = (response as List)
          .map((json) => UnitListItem.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.info('Fetched ${items.length} unit list items');
      return items;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch unit list items', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Factory Provisioning
  // ============================================================================

  /// Mark unit as factory provisioned
  ///
  /// Called after a device is successfully provisioned via Service Mode.
  /// Updates the unit status and records provisioning metadata.
  Future<Unit> markFactoryProvisioned({
    required String unitId,
    required String userId,
  }) async {
    try {
      AppLogger.info('Marking unit as factory provisioned: $unitId');

      final response = await _supabase
          .from('units')
          .update({
            'status': UnitStatus.factoryProvisioned.databaseValue,
            'factory_provisioned_at': DateTime.now().toIso8601String(),
            'factory_provisioned_by': userId,
          })
          .eq('id', unitId)
          .select()
          .single();

      final unit = Unit.fromJson(response);
      AppLogger.info('Unit marked as factory provisioned');
      return unit;
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to mark unit as factory provisioned', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Consumer Provisioning
  // ============================================================================

  /// Mark unit as user provisioned (claimed by consumer)
  ///
  /// Called when a consumer claims and provisions the unit via mobile app.
  Future<Unit> markUserProvisioned({
    required String unitId,
    required String userId,
    String? deviceName,
    Map<String, dynamic>? consumerAttributes,
  }) async {
    try {
      AppLogger.info('Marking unit as user provisioned: $unitId');

      final updateData = {
        'status': UnitStatus.userProvisioned.databaseValue,
        'user_id': userId,
        'consumer_provisioned_at': DateTime.now().toIso8601String(),
        if (deviceName != null) 'device_name': deviceName,
        if (consumerAttributes != null) 'consumer_attributes': consumerAttributes,
      };

      final response = await _supabase
          .from('units')
          .update(updateData)
          .eq('id', unitId)
          .select()
          .single();

      final unit = Unit.fromJson(response);
      AppLogger.info('Unit marked as user provisioned');
      return unit;
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to mark unit as user provisioned', error, stackTrace);
      rethrow;
    }
  }

  /// Update consumer attributes for a unit
  Future<Unit> updateConsumerAttributes({
    required String unitId,
    required Map<String, dynamic> attributes,
  }) async {
    try {
      AppLogger.info('Updating consumer attributes for unit: $unitId');

      final response = await _supabase
          .from('units')
          .update({'consumer_attributes': attributes})
          .eq('id', unitId)
          .select()
          .single();

      final unit = Unit.fromJson(response);
      AppLogger.info('Consumer attributes updated');
      return unit;
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to update consumer attributes', error, stackTrace);
      rethrow;
    }
  }

  /// Update device name for a unit
  Future<Unit> updateDeviceName({
    required String unitId,
    required String deviceName,
  }) async {
    try {
      AppLogger.info('Updating device name for unit: $unitId');

      final response = await _supabase
          .from('units')
          .update({'device_name': deviceName})
          .eq('id', unitId)
          .select()
          .single();

      final unit = Unit.fromJson(response);
      AppLogger.info('Device name updated to: $deviceName');
      return unit;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update device name', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Production Workflow
  // ============================================================================

  /// Mark a unit as production complete
  Future<Unit> markProductionComplete(String unitId) async {
    try {
      AppLogger.info('Marking unit as production complete: $unitId');

      final response = await _supabase
          .from('units')
          .update({
            'is_completed': true,
            'production_completed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', unitId)
          .select()
          .single();

      final unit = Unit.fromJson(response);
      AppLogger.info('Unit marked as production complete');
      return unit;
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to mark unit as production complete', error, stackTrace);
      rethrow;
    }
  }

  /// Start production on a unit
  Future<Unit> startProduction(String unitId) async {
    try {
      AppLogger.info('Starting production on unit: $unitId');

      final response = await _supabase
          .from('units')
          .update({
            'production_started_at': DateTime.now().toIso8601String(),
          })
          .eq('id', unitId)
          .select()
          .single();

      final unit = Unit.fromJson(response);
      AppLogger.info('Production started on unit');
      return unit;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to start production', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Unit Deletion
  // ============================================================================

  /// Delete a unit (and its QR code from storage)
  Future<void> deleteUnit(String unitId) async {
    try {
      AppLogger.info('Deleting unit: $unitId');

      // Get unit to get QR code URL
      final unit = await getUnitById(unitId);

      // Delete from database (cascade will delete related records)
      await _supabase.from('units').delete().eq('id', unitId);

      // Delete QR code from storage if present
      if (unit.qrCodeUrl != null) {
        try {
          final parts = unit.qrCodeUrl!.split('/');
          final bucket = parts[parts.indexOf('object') + 1];
          final filePath = parts.skip(parts.indexOf('object') + 2).join('/');

          await _supabase.storage.from(bucket).remove([filePath]);
          AppLogger.info('QR code deleted from storage');
        } catch (storageError) {
          AppLogger.warning(
              'Failed to delete QR code from storage: $storageError');
        }
      }

      AppLogger.info('Unit deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete unit', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // User-owned Units
  // ============================================================================

  /// Get units owned by a specific user
  Future<List<Unit>> getUnitsByUser(String userId) async {
    try {
      AppLogger.info('Fetching units for user: $userId');

      final response = await _supabase
          .from('units')
          .select()
          .eq('user_id', userId)
          .order('consumer_provisioned_at', ascending: false);

      final units =
          (response as List).map((json) => Unit.fromJson(json)).toList();

      AppLogger.info('Found ${units.length} units for user $userId');
      return units;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch units by user', error, stackTrace);
      rethrow;
    }
  }

  /// Transfer unit ownership to a new user
  Future<Unit> transferOwnership({
    required String unitId,
    required String newUserId,
  }) async {
    try {
      AppLogger.info('Transferring unit $unitId to user $newUserId');

      final response = await _supabase
          .from('units')
          .update({'user_id': newUserId})
          .eq('id', unitId)
          .select()
          .single();

      final unit = Unit.fromJson(response);
      AppLogger.info('Unit ownership transferred');
      return unit;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to transfer unit ownership', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Order Integration
  // ============================================================================

  /// Get unit for an order
  Future<Unit?> getUnitByOrder(String orderId) async {
    try {
      AppLogger.info('Fetching unit for order: $orderId');

      final response = await _supabase
          .from('units')
          .select()
          .eq('order_id', orderId)
          .maybeSingle();

      if (response == null) {
        AppLogger.info('No unit found for order: $orderId');
        return null;
      }

      final unit = Unit.fromJson(response);
      AppLogger.info('Found unit: ${unit.serialNumber}');
      return unit;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch unit by order', error, stackTrace);
      rethrow;
    }
  }

  /// Link an order to a unit
  Future<Unit> linkOrder({
    required String unitId,
    required String orderId,
  }) async {
    try {
      AppLogger.info('Linking order $orderId to unit $unitId');

      final response = await _supabase
          .from('units')
          .update({'order_id': orderId})
          .eq('id', unitId)
          .select()
          .single();

      final unit = Unit.fromJson(response);
      AppLogger.info('Order linked to unit');
      return unit;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to link order to unit', error, stackTrace);
      rethrow;
    }
  }
}
