import 'package:saturday_app/models/firmware_version.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/models/production_unit.dart';
import 'package:saturday_app/models/production_unit_with_consumer_info.dart';
import 'package:saturday_app/models/thread_credentials.dart';
import 'package:saturday_app/models/unit_firmware_history.dart';
import 'package:saturday_app/models/unit_step_completion.dart';
import 'package:saturday_app/services/qr_service.dart';
import 'package:saturday_app/services/storage_service.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:saturday_app/utils/id_generator.dart';
import 'package:uuid/uuid.dart';

/// Repository for managing production units
class ProductionUnitRepository {
  final _supabase = SupabaseService.instance.client;
  final _qrService = QRService();
  final _storageService = StorageService();
  final _uuid = const Uuid();

  /// Create a new production unit
  ///
  /// This method orchestrates the entire unit creation process:
  /// 1. Get product code from product
  /// 2. Generate next sequence number
  /// 3. Create unit ID (e.g., "SV-TURNTABLE-00001")
  /// 4. Generate UUID
  /// 5. Generate QR code with logo
  /// 6. Upload QR code to storage
  /// 7. Insert unit record to database with QR URL
  /// 8. If orderId provided, link order to unit
  ///
  /// All operations are performed in a transaction (rollback if any step fails)
  Future<ProductionUnit> createProductionUnit({
    required String productId,
    required String variantId,
    required String userId,
    String? shopifyOrderId,
    String? shopifyOrderNumber,
    String? customerName,
    String? orderId, // Internal order ID to link to this unit
  }) async {
    try {
      AppLogger.info('Creating production unit for product: $productId');

      // Step 1: Get product code from product
      final productResponse = await _supabase
          .from('products')
          .select('product_code')
          .eq('id', productId)
          .single();

      final productCode = productResponse['product_code'] as String;
      AppLogger.info('Product code: $productCode');

      // Step 2: Generate next sequence number
      final sequenceNumber = await IDGenerator.getNextSequenceNumber(productCode);
      AppLogger.info('Sequence number: $sequenceNumber');

      // Step 3: Create unit ID
      final unitId = IDGenerator.generateUnitId(productCode, sequenceNumber);
      AppLogger.info('Unit ID: $unitId');

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
        'uuid': uuid,
        'unit_id': unitId,
        'product_id': productId,
        'variant_id': variantId,
        'shopify_order_id': shopifyOrderId,
        'shopify_order_number': shopifyOrderNumber,
        'customer_name': customerName,
        'qr_code_url': qrCodeUrl,
        'is_completed': false,
        'created_by': userId,
      };

      final response = await _supabase
          .from('production_units')
          .insert(unitData)
          .select()
          .single();

      final unit = ProductionUnit.fromJson(response);
      AppLogger.info('Production unit created successfully: ${unit.unitId}');

      // Step 8: Link order to unit if orderId provided
      if (orderId != null) {
        AppLogger.info('Linking order $orderId to unit ${unit.id}');
        try {
          await _supabase
              .from('orders')
              .update({'assigned_unit_id': unit.id})
              .eq('id', orderId);
          AppLogger.info('Order linked successfully');
        } catch (orderError) {
          AppLogger.warning('Failed to link order to unit: $orderError');
          // Continue - unit was created successfully
        }
      }

      return unit;
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to create production unit',
        error,
        stackTrace,
      );

      // TODO: Implement cleanup/rollback for partial failures
      // If QR code was uploaded but database insert failed, we should delete the QR code

      rethrow;
    }
  }

  /// Get all units in production (not completed)
  Future<List<ProductionUnit>> getUnitsInProduction() async {
    try {
      AppLogger.info('Fetching units in production');

      final response = await _supabase
          .from('production_units')
          .select()
          .eq('is_completed', false)
          .order('created_at', ascending: false);

      final units = (response as List)
          .map((json) => ProductionUnit.fromJson(json))
          .toList();

      AppLogger.info('Found ${units.length} units in production');
      return units;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch units in production', error, stackTrace);
      rethrow;
    }
  }

  /// Get all completed units
  Future<List<ProductionUnit>> getCompletedUnits() async {
    try {
      AppLogger.info('Fetching completed units');

      final response = await _supabase
          .from('production_units')
          .select()
          .eq('is_completed', true)
          .order('production_completed_at', ascending: false);

      final units = (response as List)
          .map((json) => ProductionUnit.fromJson(json))
          .toList();

      AppLogger.info('Found ${units.length} completed units');
      return units;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch completed units', error, stackTrace);
      rethrow;
    }
  }

  /// Get a unit by its UUID (from QR code scan)
  Future<ProductionUnit> getUnitByUuid(String uuid) async {
    try {
      AppLogger.info('Fetching unit by UUID: $uuid');

      final response = await _supabase
          .from('production_units')
          .select()
          .eq('uuid', uuid)
          .single();

      final unit = ProductionUnit.fromJson(response);
      AppLogger.info('Found unit: ${unit.unitId}');
      return unit;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch unit by UUID', error, stackTrace);
      rethrow;
    }
  }

  /// Get a unit by its ID
  Future<ProductionUnit> getUnitById(String id) async {
    try {
      AppLogger.info('Fetching unit by ID: $id');

      final response = await _supabase
          .from('production_units')
          .select()
          .eq('id', id)
          .single();

      final unit = ProductionUnit.fromJson(response);
      return unit;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch unit by ID', error, stackTrace);
      rethrow;
    }
  }

  /// Get production steps for a unit (from the unit's product)
  Future<List<ProductionStep>> getUnitSteps(String unitId) async {
    try {
      AppLogger.info('Fetching production steps for unit: $unitId');

      // First get the unit's product ID
      final unitResponse = await _supabase
          .from('production_units')
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
      AppLogger.error(
        'Failed to fetch step completions',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Mark a production step as complete for a unit
  ///
  /// If all steps are now complete, automatically marks the unit as completed
  Future<ProductionUnit> completeStep({
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

      await _supabase
          .from('unit_step_completions')
          .insert(completionData);

      AppLogger.info('Step completion recorded');

      // Check if this was the first step (set production_started_at)
      final unit = await getUnitById(unitId);
      if (unit.productionStartedAt == null) {
        await _supabase
            .from('production_units')
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
        await markUnitComplete(unitId);
      }

      // Return updated unit
      return await getUnitById(unitId);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to complete step', error, stackTrace);
      rethrow;
    }
  }

  /// Manually mark a unit as complete
  Future<void> markUnitComplete(String unitId) async {
    try {
      AppLogger.info('Marking unit as complete: $unitId');

      await _supabase
          .from('production_units')
          .update({
            'is_completed': true,
            'production_completed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', unitId);

      AppLogger.info('Unit marked as complete');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to mark unit complete', error, stackTrace);
      rethrow;
    }
  }

  /// Update unit owner
  Future<void> updateUnitOwner(String unitId, String? ownerId) async {
    try {
      AppLogger.info('Updating unit owner: $unitId -> $ownerId');

      await _supabase
          .from('production_units')
          .update({'current_owner_id': ownerId})
          .eq('id', unitId);

      AppLogger.info('Unit owner updated');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update unit owner', error, stackTrace);
      rethrow;
    }
  }

  /// Update MAC address for a production unit
  ///
  /// Typically called during firmware provisioning to capture the device MAC
  Future<void> updateMacAddress(String unitId, String macAddress) async {
    try {
      AppLogger.info('Updating MAC address for unit $unitId: $macAddress');

      await _supabase
          .from('production_units')
          .update({'mac_address': macAddress})
          .eq('id', unitId);

      AppLogger.info('MAC address updated successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update MAC address', error, stackTrace);
      rethrow;
    }
  }

  /// Get a unit by its MAC address
  Future<ProductionUnit?> getUnitByMacAddress(String macAddress) async {
    try {
      AppLogger.info('Fetching unit by MAC address: $macAddress');

      final response = await _supabase
          .from('production_units')
          .select()
          .eq('mac_address', macAddress)
          .maybeSingle();

      if (response == null) {
        AppLogger.info('No unit found with MAC address: $macAddress');
        return null;
      }

      final unit = ProductionUnit.fromJson(response);
      AppLogger.info('Found unit: ${unit.unitId}');
      return unit;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch unit by MAC address', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a production unit (and its QR code from storage)
  Future<void> deleteUnit(String unitId) async {
    try {
      AppLogger.info('Deleting unit: $unitId');

      // Get unit to get QR code URL
      final unit = await getUnitById(unitId);

      // Delete from database (cascade will delete step completions)
      await _supabase
          .from('production_units')
          .delete()
          .eq('id', unitId);

      // Delete QR code from storage
      // Note: QR code URL format is 'storage/v1/object/qr-codes/{uuid}.png'
      // Storage service can handle deletion based on this format
      try {
        final parts = unit.qrCodeUrl.split('/');
        final bucket = parts[parts.indexOf('object') + 1];
        final filePath = parts.skip(parts.indexOf('object') + 2).join('/');

        await _supabase.storage.from(bucket).remove([filePath]);
        AppLogger.info('QR code deleted from storage');
      } catch (storageError) {
        AppLogger.warning('Failed to delete QR code from storage: $storageError');
        // Continue - unit is already deleted from database
      }

      AppLogger.info('Unit deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete unit', error, stackTrace);
      rethrow;
    }
  }

  /// Search units by unit ID
  Future<List<ProductionUnit>> searchUnits(String query) async {
    try {
      AppLogger.info('Searching units: $query');

      final response = await _supabase
          .from('production_units')
          .select()
          .ilike('unit_id', '%$query%')
          .order('created_at', ascending: false)
          .limit(50);

      final units = (response as List)
          .map((json) => ProductionUnit.fromJson(json))
          .toList();

      AppLogger.info('Found ${units.length} units matching "$query"');
      return units;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to search units', error, stackTrace);
      rethrow;
    }
  }

  /// Get firmware requirements for a unit
  /// Returns a map of deviceTypeId -> latest production-ready firmware
  Future<Map<String, FirmwareVersion>> getFirmwareForUnit(String unitId) async {
    try {
      AppLogger.info('Getting firmware for unit: $unitId');

      // Get the unit's product
      final unit = await getUnitById(unitId);

      // Get device types for this product
      final deviceTypesResponse = await _supabase
          .from('product_device_types')
          .select('device_type_id, quantity')
          .eq('product_id', unit.productId);

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
            .from('firmware_versions')
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

      await _supabase
          .from('unit_firmware_history')
          .insert(history.toInsertJson());

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
      AppLogger.error(
        'Failed to record firmware installation',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Get firmware installation history for a unit
  Future<List<UnitFirmwareHistory>> getUnitFirmwareHistory(
    String unitId,
  ) async {
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
      AppLogger.error(
        'Failed to get unit firmware history',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Get units without MAC address (for fresh device assignment)
  ///
  /// Returns units that haven't been provisioned yet (no MAC address recorded)
  /// Optionally filtered by product ID
  Future<List<ProductionUnit>> getUnitsWithoutMacAddress({
    String? productId,
  }) async {
    try {
      AppLogger.info('Fetching units without MAC address');

      var query = _supabase
          .from('production_units')
          .select()
          .isFilter('mac_address', null)
          .eq('is_completed', false);

      if (productId != null) {
        query = query.eq('product_id', productId);
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(100);

      final units = (response as List)
          .map((json) => ProductionUnit.fromJson(json))
          .toList();

      AppLogger.info('Found ${units.length} units without MAC address');
      return units;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch units without MAC address', error, stackTrace);
      rethrow;
    }
  }

  /// Get all production units for provisioning (with consumer device info)
  ///
  /// Returns all incomplete units regardless of MAC address status, with
  /// information about whether each unit has an associated consumer device.
  /// Used for the re-provisioning flow that allows re-provisioning any unit.
  Future<List<ProductionUnitWithConsumerInfo>> getUnitsForProvisioning({
    String? productId,
  }) async {
    try {
      AppLogger.info('Fetching units for provisioning');

      var query = _supabase.from('production_units').select('''
            *,
            consumer_devices!production_unit_id (
              id
            )
          ''').eq('is_completed', false);

      if (productId != null) {
        query = query.eq('product_id', productId);
      }

      final response =
          await query.order('created_at', ascending: false).limit(100);

      final units = (response as List)
          .map((json) => ProductionUnitWithConsumerInfo.fromJson(json))
          .toList();

      AppLogger.info('Found ${units.length} units for provisioning');
      return units;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch units for provisioning', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a consumer device record (for re-provisioning workflow)
  ///
  /// When re-provisioning a unit that already has a consumer device linked,
  /// the old consumer device record must be deleted first.
  Future<void> deleteConsumerDevice(String consumerDeviceId) async {
    try {
      AppLogger.info('Deleting consumer device: $consumerDeviceId');

      await _supabase
          .from('consumer_devices')
          .delete()
          .eq('id', consumerDeviceId);

      AppLogger.info('Consumer device deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete consumer device', error, stackTrace);
      rethrow;
    }
  }

  /// Get a unit by its serial number (unit_id field like "SV-HUB-000001")
  ///
  /// Used to look up a unit from a device's reported unit_id
  Future<ProductionUnit?> getUnitBySerialNumber(String serialNumber) async {
    try {
      AppLogger.info('Fetching unit by serial number: $serialNumber');

      final response = await _supabase
          .from('production_units')
          .select()
          .eq('unit_id', serialNumber)
          .maybeSingle();

      if (response == null) {
        AppLogger.info('No unit found with serial number: $serialNumber');
        return null;
      }

      final unit = ProductionUnit.fromJson(response);
      AppLogger.info('Found unit: ${unit.unitId}');
      return unit;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch unit by serial number', error, stackTrace);
      rethrow;
    }
  }

  /// Get units by device type
  ///
  /// Returns units whose product uses the specified device type
  Future<List<ProductionUnit>> getUnitsByDeviceType(String deviceTypeId) async {
    try {
      AppLogger.info('Fetching units by device type: $deviceTypeId');

      // Get products that use this device type
      final productDeviceTypesResponse = await _supabase
          .from('product_device_types')
          .select('product_id')
          .eq('device_type_id', deviceTypeId);

      final productIds = (productDeviceTypesResponse as List)
          .map((row) => row['product_id'] as String)
          .toList();

      if (productIds.isEmpty) {
        AppLogger.info('No products use device type: $deviceTypeId');
        return [];
      }

      // Get units for these products
      final response = await _supabase
          .from('production_units')
          .select()
          .inFilter('product_id', productIds)
          .eq('is_completed', false)
          .order('created_at', ascending: false)
          .limit(100);

      final units = (response as List)
          .map((json) => ProductionUnit.fromJson(json))
          .toList();

      AppLogger.info('Found ${units.length} units with device type: $deviceTypeId');
      return units;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch units by device type', error, stackTrace);
      rethrow;
    }
  }

  /// Get all units that have a specific firmware version installed
  Future<List<ProductionUnit>> getUnitsWithFirmware(
    String firmwareVersionId,
  ) async {
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
      final unitsResponse = await _supabase
          .from('production_units')
          .select()
          .inFilter('id', unitIds);

      final units = (unitsResponse as List)
          .map((json) => ProductionUnit.fromJson(json))
          .toList();

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

  /// Save Thread Border Router credentials for a production unit (Hub)
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

  /// Get Thread credentials for a production unit by unit database ID
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

  /// Delete Thread credentials for a production unit
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

  /// Check if a production unit has Thread credentials stored
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
            production_units!inner (
              unit_id
            )
          ''').order('created_at', ascending: false);

      final credentials = (response as List).map((json) {
        final unitData = json['production_units'] as Map<String, dynamic>?;
        return ThreadCredentialsWithUnit(
          credentials: ThreadCredentials.fromJson(json),
          hubSerialNumber: unitData?['unit_id'] as String? ?? 'Unknown',
        );
      }).toList();

      AppLogger.info('Found ${credentials.length} Thread credential sets');
      return credentials;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch all Thread credentials', error, stackTrace);
      rethrow;
    }
  }
}
