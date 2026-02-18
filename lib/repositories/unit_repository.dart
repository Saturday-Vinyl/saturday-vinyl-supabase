import 'package:saturday_app/models/firmware_version.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/models/thread_credentials.dart';
import 'package:saturday_app/models/unit.dart';
import 'package:saturday_app/models/unit_filter.dart';
import 'package:saturday_app/models/unit_firmware_history.dart';
import 'package:saturday_app/models/unit_list_item.dart';
import 'package:saturday_app/models/unit_step_completion.dart';
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

  /// Search units filtered by device type slug
  ///
  /// Finds units whose products use the specified device type.
  /// Optionally filters by serial number search query.
  Future<List<Unit>> searchUnitsByDeviceType({
    required String deviceTypeSlug,
    String? searchQuery,
  }) async {
    try {
      AppLogger.info(
          'Searching units for device type: $deviceTypeSlug, query: $searchQuery');

      // First, get the device type ID from the slug
      final deviceTypeResponse = await _supabase
          .from('device_types')
          .select('id')
          .eq('slug', deviceTypeSlug)
          .maybeSingle();

      if (deviceTypeResponse == null) {
        AppLogger.warning('Device type not found: $deviceTypeSlug');
        // Fall back to searching all units if device type not found
        return searchQuery != null && searchQuery.isNotEmpty
            ? searchUnits(searchQuery)
            : [];
      }

      final deviceTypeId = deviceTypeResponse['id'] as String;

      // Get product IDs that use this device type
      final productDeviceTypesResponse = await _supabase
          .from('product_device_types')
          .select('product_id')
          .eq('device_type_id', deviceTypeId);

      final productIds = (productDeviceTypesResponse as List)
          .map((item) => item['product_id'] as String)
          .toList();

      if (productIds.isEmpty) {
        AppLogger.info('No products use device type: $deviceTypeSlug');
        return [];
      }

      // Build the units query
      var queryBuilder = _supabase
          .from('units')
          .select()
          .inFilter('product_id', productIds);

      // Add serial number filter if search query provided
      if (searchQuery != null && searchQuery.isNotEmpty) {
        queryBuilder = queryBuilder.ilike('serial_number', '%$searchQuery%');
      }

      final response =
          await queryBuilder.order('created_at', ascending: false).limit(50);

      final units =
          (response as List).map((json) => Unit.fromJson(json)).toList();

      AppLogger.info(
          'Found ${units.length} units for device type $deviceTypeSlug');
      return units;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to search units by device type', error, stackTrace);
      rethrow;
    }
  }

  /// Check if a unit already has a device of a specific type provisioned
  ///
  /// Returns true if the unit already has a device with the given device type slug.
  Future<bool> unitHasDeviceOfType({
    required String unitId,
    required String deviceTypeSlug,
  }) async {
    try {
      final response = await _supabase
          .from('devices')
          .select('id')
          .eq('unit_id', unitId)
          .eq('device_type_slug', deviceTypeSlug)
          .limit(1);

      return (response as List).isNotEmpty;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to check device type for unit', error, stackTrace);
      return false; // Fail open - don't block provisioning
    }
  }

  /// Get units with their device type provisioning status
  ///
  /// Returns a map of unit IDs to whether they have a device of the given type.
  Future<Map<String, bool>> getUnitsDeviceTypeStatus({
    required List<String> unitIds,
    required String deviceTypeSlug,
  }) async {
    try {
      if (unitIds.isEmpty) return {};

      final response = await _supabase
          .from('devices')
          .select('unit_id')
          .inFilter('unit_id', unitIds)
          .eq('device_type_slug', deviceTypeSlug);

      final unitsWithDevice =
          (response as List).map((item) => item['unit_id'] as String).toSet();

      return {
        for (final unitId in unitIds) unitId: unitsWithDevice.contains(unitId)
      };
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to get device type status for units', error, stackTrace);
      return {for (final unitId in unitIds) unitId: false};
    }
  }

  // ============================================================================
  // Dashboard View
  // ============================================================================

  /// Get unit list items for dashboard display
  ///
  /// Queries `units` table directly with a `devices` join for primary device
  /// engineering data. Supports filtering and sorting.
  Future<List<UnitListItem>> getUnitListItems({UnitFilter? filter}) async {
    try {
      AppLogger.info('Fetching unit list items with filter: $filter');

      // Build query with device join
      var queryBuilder = _supabase.from('units').select('''
        *,
        devices (id, mac_address, device_type_slug, latest_telemetry)
      ''');

      // Apply status filter
      if (filter?.status != null) {
        queryBuilder = queryBuilder.eq('status', filter!.status!.databaseValue);
      }

      // Apply online filter
      if (filter?.isOnline != null) {
        queryBuilder = queryBuilder.eq('is_online', filter!.isOnline!);
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
  // Production Steps
  // ============================================================================

  /// Get production steps for a unit (from the unit's product)
  Future<List<ProductionStep>> getUnitSteps(String unitId) async {
    try {
      AppLogger.info('Fetching production steps for unit: $unitId');

      // First get the unit's product ID
      final unitResponse = await _supabase
          .from('units')
          .select('product_id')
          .eq('id', unitId)
          .single();

      final productId = unitResponse['product_id'] as String;

      // Then get the production steps for that product
      final stepsResponse = await _supabase
          .from('production_steps')
          .select()
          .eq('product_id', productId)
          .order('step_order', ascending: true);

      final steps = (stepsResponse as List)
          .map((json) => ProductionStep.fromJson(json))
          .toList();

      AppLogger.info('Found ${steps.length} production steps');
      return steps;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch unit steps', error, stackTrace);
      rethrow;
    }
  }

  /// Get completed steps for a unit
  Future<List<UnitStepCompletion>> getUnitStepCompletions(String unitId) async {
    try {
      AppLogger.info('Fetching step completions for unit: $unitId');

      final response = await _supabase
          .from('unit_step_completions')
          .select()
          .eq('unit_id', unitId)
          .order('completed_at', ascending: true);

      final completions = (response as List)
          .map((json) => UnitStepCompletion.fromJson(json))
          .toList();

      AppLogger.info('Found ${completions.length} completed steps');
      return completions;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch step completions', error, stackTrace);
      rethrow;
    }
  }

  /// Mark a production step as complete for a unit
  ///
  /// If all steps are now complete, automatically marks the unit as completed
  Future<Unit> completeStep({
    required String unitId,
    required String stepId,
    required String userId,
    String? notes,
  }) async {
    try {
      AppLogger.info('Completing step $stepId for unit $unitId');

      // Create step completion record
      final completionData = {
        'unit_id': unitId,
        'step_id': stepId,
        'completed_by': userId,
        'notes': notes,
      };

      await _supabase.from('unit_step_completions').insert(completionData);

      AppLogger.info('Step completion recorded');

      // Check if this was the first step (set production_started_at)
      final unit = await getUnitById(unitId);
      if (unit.productionStartedAt == null) {
        await _supabase
            .from('units')
            .update({'production_started_at': DateTime.now().toIso8601String()})
            .eq('id', unitId);

        AppLogger.info('Set production_started_at for unit');
      }

      // Check if all steps are complete
      final allSteps = await getUnitSteps(unitId);
      final completedSteps = await getUnitStepCompletions(unitId);

      final allStepsComplete = allSteps.length == completedSteps.length;

      if (allStepsComplete) {
        AppLogger.info('All steps complete - marking unit as complete');
        await markProductionComplete(unitId);
      }

      // Return updated unit
      return await getUnitById(unitId);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to complete step', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Firmware Management
  // ============================================================================

  /// Get firmware requirements for a unit
  /// Returns a map of deviceTypeId -> latest production-ready firmware
  Future<Map<String, FirmwareVersion>> getFirmwareForUnit(String unitId) async {
    try {
      AppLogger.info('Getting firmware for unit: $unitId');

      // Get the unit's product
      final unit = await getUnitById(unitId);

      if (unit.productId == null) {
        AppLogger.info('Unit $unitId has no product assigned');
        return {};
      }

      // Get device types for this product
      final deviceTypesResponse = await _supabase
          .from('product_device_types')
          .select('device_type_id, quantity')
          .eq('product_id', unit.productId!);

      final deviceTypeIds = (deviceTypesResponse as List)
          .map((row) => row['device_type_id'] as String)
          .toList();

      if (deviceTypeIds.isEmpty) {
        AppLogger.info('No device types found for unit $unitId');
        return {};
      }

      // Get latest production-ready firmware for each device type
      final firmwareMap = <String, FirmwareVersion>{};

      for (final deviceTypeId in deviceTypeIds) {
        final firmwareResponse = await _supabase
            .from('firmware')
            .select()
            .eq('device_type_id', deviceTypeId)
            .eq('is_production_ready', true)
            .order('created_at', ascending: false)
            .limit(1);

        if (firmwareResponse.isNotEmpty) {
          final firmware = FirmwareVersion.fromJson(firmwareResponse.first);
          firmwareMap[deviceTypeId] = firmware;
        }
      }

      AppLogger.info('Found firmware for ${firmwareMap.length} device types');
      return firmwareMap;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get firmware for unit', error, stackTrace);
      rethrow;
    }
  }

  /// Record a firmware installation on a unit
  ///
  /// If [stepId] is provided, marks that production step as complete after recording
  Future<UnitFirmwareHistory> recordFirmwareInstallation({
    required String unitId,
    required String deviceTypeId,
    required String firmwareVersionId,
    required String userId,
    String? installationMethod,
    String? notes,
    String? stepId,
  }) async {
    try {
      AppLogger.info('Recording firmware installation for unit: $unitId');

      final history = UnitFirmwareHistory(
        id: _uuid.v4(),
        unitId: unitId,
        deviceTypeId: deviceTypeId,
        firmwareVersionId: firmwareVersionId,
        installedAt: DateTime.now(),
        installedBy: userId,
        installationMethod: installationMethod,
        notes: notes,
      );

      await _supabase.from('unit_firmware_history').insert(history.toInsertJson());

      AppLogger.info('Firmware installation recorded successfully');

      // Mark the production step as complete if stepId is provided
      if (stepId != null) {
        AppLogger.info('Marking firmware provisioning step as complete: $stepId');
        await completeStep(
          unitId: unitId,
          stepId: stepId,
          userId: userId,
          notes: notes,
        );
      }

      return history;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to record firmware installation', error, stackTrace);
      rethrow;
    }
  }

  /// Get firmware installation history for a unit
  Future<List<UnitFirmwareHistory>> getUnitFirmwareHistory(String unitId) async {
    try {
      AppLogger.info('Getting firmware history for unit: $unitId');

      final response = await _supabase
          .from('unit_firmware_history')
          .select()
          .eq('unit_id', unitId)
          .order('installed_at', ascending: false);

      final history = (response as List)
          .map((json) => UnitFirmwareHistory.fromJson(json))
          .toList();

      AppLogger.info('Found ${history.length} firmware installation records');
      return history;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get unit firmware history', error, stackTrace);
      rethrow;
    }
  }

  /// Get all units that have a specific firmware version installed
  Future<List<Unit>> getUnitsWithFirmware(String firmwareVersionId) async {
    try {
      AppLogger.info('Getting units with firmware: $firmwareVersionId');

      final response = await _supabase
          .from('unit_firmware_history')
          .select('unit_id')
          .eq('firmware_version_id', firmwareVersionId);

      final unitIds = (response as List)
          .map((row) => row['unit_id'] as String)
          .toSet() // Remove duplicates
          .toList();

      if (unitIds.isEmpty) {
        return [];
      }

      // Get the actual unit records
      final unitsResponse =
          await _supabase.from('units').select().inFilter('id', unitIds);

      final units =
          (unitsResponse as List).map((json) => Unit.fromJson(json)).toList();

      AppLogger.info('Found ${units.length} units with this firmware');
      return units;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get units with firmware', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Thread Credentials
  // ============================================================================

  /// Save Thread Border Router credentials for a unit (Hub)
  ///
  /// These credentials are captured during Hub provisioning and used by the
  /// mobile app to provision crates to join the Thread network.
  ///
  /// If credentials already exist for this unit, they will be updated.
  Future<ThreadCredentials> saveThreadCredentials(
    ThreadCredentials credentials,
  ) async {
    try {
      AppLogger.info('Saving Thread credentials for unit: ${credentials.unitId}');

      // Validate credentials before saving
      final validationError = credentials.validate();
      if (validationError != null) {
        throw Exception('Invalid Thread credentials: $validationError');
      }

      // Use upsert to handle both insert and update
      final response = await _supabase
          .from('thread_credentials')
          .upsert(
            credentials.toInsertJson(),
            onConflict: 'unit_id',
          )
          .select()
          .single();

      final saved = ThreadCredentials.fromJson(response);
      AppLogger.info('Thread credentials saved successfully');
      return saved;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to save Thread credentials', error, stackTrace);
      rethrow;
    }
  }

  /// Get Thread credentials for a unit by unit database ID
  Future<ThreadCredentials?> getThreadCredentials(String unitId) async {
    try {
      AppLogger.info('Fetching Thread credentials for unit: $unitId');

      final response = await _supabase
          .from('thread_credentials')
          .select()
          .eq('unit_id', unitId)
          .maybeSingle();

      if (response == null) {
        AppLogger.info('No Thread credentials found for unit: $unitId');
        return null;
      }

      final credentials = ThreadCredentials.fromJson(response);
      AppLogger.info('Found Thread credentials: ${credentials.networkName}');
      return credentials;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch Thread credentials', error, stackTrace);
      rethrow;
    }
  }

  /// Get Thread credentials by unit serial number (e.g., "SV-HUB-00001")
  ///
  /// This is useful when the mobile app knows the Hub's serial number
  /// and needs to get the Thread credentials to provision a crate.
  Future<ThreadCredentials?> getThreadCredentialsBySerialNumber(
    String serialNumber,
  ) async {
    try {
      AppLogger.info('Fetching Thread credentials by serial: $serialNumber');

      // First get the unit ID
      final unit = await getUnitBySerialNumber(serialNumber);
      if (unit == null) {
        AppLogger.info('Unit not found: $serialNumber');
        return null;
      }

      return await getThreadCredentials(unit.id);
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to fetch Thread credentials by serial',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Delete Thread credentials for a unit
  Future<void> deleteThreadCredentials(String unitId) async {
    try {
      AppLogger.info('Deleting Thread credentials for unit: $unitId');

      await _supabase.from('thread_credentials').delete().eq('unit_id', unitId);

      AppLogger.info('Thread credentials deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete Thread credentials', error, stackTrace);
      rethrow;
    }
  }

  /// Check if a unit has Thread credentials stored
  Future<bool> hasThreadCredentials(String unitId) async {
    try {
      final response = await _supabase
          .from('thread_credentials')
          .select('id')
          .eq('unit_id', unitId)
          .maybeSingle();

      return response != null;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to check Thread credentials', error, stackTrace);
      rethrow;
    }
  }

  /// Get all available Thread credentials (from provisioned Hubs)
  ///
  /// Used when testing Thread on non-BR devices that need to join
  /// an existing Thread network. Returns credentials with the associated
  /// Hub's serial number for display purposes.
  Future<List<ThreadCredentialsWithUnit>> getAllThreadCredentials() async {
    try {
      AppLogger.info('Fetching all Thread credentials');

      final response = await _supabase.from('thread_credentials').select('''
            *,
            units!inner (
              serial_number
            )
          ''').order('created_at', ascending: false);

      final credentials = (response as List).map((json) {
        final unitData = json['units'] as Map<String, dynamic>?;
        return ThreadCredentialsWithUnit(
          credentials: ThreadCredentials.fromJson(json),
          hubSerialNumber: unitData?['serial_number'] as String? ?? 'Unknown',
        );
      }).toList();

      AppLogger.info('Found ${credentials.length} Thread credential sets');
      return credentials;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch all Thread credentials', error, stackTrace);
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

      // Disassociate any devices linked to this unit
      await _supabase
          .from('devices')
          .update({'unit_id': null})
          .eq('unit_id', unitId);
      AppLogger.info('Disassociated devices from unit');

      // Delete from database
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
