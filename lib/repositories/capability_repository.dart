import 'package:saturday_app/models/capability.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Repository for managing device capabilities
///
/// Capabilities are templates that define configurable features of Saturday devices.
/// Each capability has attribute schemas for factory/consumer provisioning,
/// heartbeat data, and optional tests.
class CapabilityRepository {
  final _supabase = SupabaseService.instance.client;

  // ============================================================================
  // Capability Retrieval
  // ============================================================================

  /// Get all capabilities
  Future<List<Capability>> getAllCapabilities() async {
    try {
      AppLogger.info('Fetching all capabilities');

      final response = await _supabase
          .from('capabilities')
          .select()
          .order('name', ascending: true);

      final capabilities =
          (response as List).map((json) => Capability.fromJson(json)).toList();

      AppLogger.info('Found ${capabilities.length} capabilities');
      return capabilities;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch capabilities', error, stackTrace);
      rethrow;
    }
  }

  /// Get all active capabilities
  Future<List<Capability>> getActiveCapabilities() async {
    try {
      AppLogger.info('Fetching active capabilities');

      final response = await _supabase
          .from('capabilities')
          .select()
          .eq('is_active', true)
          .order('name', ascending: true);

      final capabilities =
          (response as List).map((json) => Capability.fromJson(json)).toList();

      AppLogger.info('Found ${capabilities.length} active capabilities');
      return capabilities;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch active capabilities', error, stackTrace);
      rethrow;
    }
  }

  /// Get a capability by ID
  Future<Capability> getCapabilityById(String id) async {
    try {
      AppLogger.info('Fetching capability by ID: $id');

      final response = await _supabase
          .from('capabilities')
          .select()
          .eq('id', id)
          .single();

      final capability = Capability.fromJson(response);
      return capability;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch capability by ID', error, stackTrace);
      rethrow;
    }
  }

  /// Get a capability by name
  Future<Capability?> getCapabilityByName(String name) async {
    try {
      AppLogger.info('Fetching capability by name: $name');

      final response = await _supabase
          .from('capabilities')
          .select()
          .eq('name', name)
          .maybeSingle();

      if (response == null) {
        AppLogger.info('No capability found with name: $name');
        return null;
      }

      final capability = Capability.fromJson(response);
      AppLogger.info('Found capability: ${capability.name}');
      return capability;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch capability by name', error, stackTrace);
      rethrow;
    }
  }

  /// Get capabilities for a device type
  ///
  /// Uses the device_type_capabilities junction table.
  Future<List<Capability>> getCapabilitiesForDeviceType(
      String deviceTypeId) async {
    try {
      AppLogger.info('Fetching capabilities for device type: $deviceTypeId');

      final response = await _supabase
          .from('device_type_capabilities')
          .select('capability_id, capabilities!inner(*)')
          .eq('device_type_id', deviceTypeId);

      final capabilities = (response as List)
          .map((json) =>
              Capability.fromJson(json['capabilities'] as Map<String, dynamic>))
          .toList();

      AppLogger.info(
          'Found ${capabilities.length} capabilities for device type $deviceTypeId');
      return capabilities;
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to fetch capabilities for device type', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Capability Creation
  // ============================================================================

  /// Create a new capability
  Future<Capability> createCapability(Capability capability) async {
    try {
      AppLogger.info('Creating capability: ${capability.name}');

      final response = await _supabase
          .from('capabilities')
          .insert(capability.toInsertJson())
          .select()
          .single();

      final created = Capability.fromJson(response);
      AppLogger.info('Capability created: ${created.name}');
      return created;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create capability', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Capability Updates
  // ============================================================================

  /// Update a capability
  Future<Capability> updateCapability(Capability capability) async {
    try {
      AppLogger.info('Updating capability: ${capability.id}');

      final response = await _supabase
          .from('capabilities')
          .update(capability.toInsertJson())
          .eq('id', capability.id)
          .select()
          .single();

      final updated = Capability.fromJson(response);
      AppLogger.info('Capability updated: ${updated.name}');
      return updated;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update capability', error, stackTrace);
      rethrow;
    }
  }

  /// Activate a capability
  Future<Capability> activateCapability(String id) async {
    try {
      AppLogger.info('Activating capability: $id');

      final response = await _supabase
          .from('capabilities')
          .update({'is_active': true})
          .eq('id', id)
          .select()
          .single();

      final capability = Capability.fromJson(response);
      AppLogger.info('Capability activated');
      return capability;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to activate capability', error, stackTrace);
      rethrow;
    }
  }

  /// Deactivate a capability
  Future<Capability> deactivateCapability(String id) async {
    try {
      AppLogger.info('Deactivating capability: $id');

      final response = await _supabase
          .from('capabilities')
          .update({'is_active': false})
          .eq('id', id)
          .select()
          .single();

      final capability = Capability.fromJson(response);
      AppLogger.info('Capability deactivated');
      return capability;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to deactivate capability', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Device Type Capability Assignment
  // ============================================================================

  /// Assign a capability to a device type
  Future<void> assignCapabilityToDeviceType({
    required String deviceTypeId,
    required String capabilityId,
  }) async {
    try {
      AppLogger.info(
          'Assigning capability $capabilityId to device type $deviceTypeId');

      await _supabase.from('device_type_capabilities').insert({
        'device_type_id': deviceTypeId,
        'capability_id': capabilityId,
      });

      AppLogger.info('Capability assigned to device type');
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to assign capability to device type', error, stackTrace);
      rethrow;
    }
  }

  /// Remove a capability from a device type
  Future<void> removeCapabilityFromDeviceType({
    required String deviceTypeId,
    required String capabilityId,
  }) async {
    try {
      AppLogger.info(
          'Removing capability $capabilityId from device type $deviceTypeId');

      await _supabase
          .from('device_type_capabilities')
          .delete()
          .eq('device_type_id', deviceTypeId)
          .eq('capability_id', capabilityId);

      AppLogger.info('Capability removed from device type');
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to remove capability from device type', error, stackTrace);
      rethrow;
    }
  }

  /// Set capabilities for a device type (replace all)
  Future<void> setCapabilitiesForDeviceType({
    required String deviceTypeId,
    required List<String> capabilityIds,
  }) async {
    try {
      AppLogger.info(
          'Setting ${capabilityIds.length} capabilities for device type $deviceTypeId');

      // Delete existing assignments
      await _supabase
          .from('device_type_capabilities')
          .delete()
          .eq('device_type_id', deviceTypeId);

      // Insert new assignments
      if (capabilityIds.isNotEmpty) {
        final assignments = capabilityIds
            .map((capId) => {
                  'device_type_id': deviceTypeId,
                  'capability_id': capId,
                })
            .toList();

        await _supabase.from('device_type_capabilities').insert(assignments);
      }

      AppLogger.info('Capabilities set for device type');
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to set capabilities for device type', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Capability Deletion
  // ============================================================================

  /// Delete a capability
  ///
  /// This will also remove all device type assignments via cascade.
  Future<void> deleteCapability(String id) async {
    try {
      AppLogger.info('Deleting capability: $id');

      await _supabase.from('capabilities').delete().eq('id', id);

      AppLogger.info('Capability deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete capability', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Schema Helpers
  // ============================================================================

  /// Get combined factory input schema for a device type
  ///
  /// Merges all capability factory_input_schema for the device type.
  /// Used by factory provisioning apps (UART/WebSocket).
  Future<Map<String, dynamic>> getFactoryInputSchemaForDeviceType(
      String deviceTypeId) async {
    try {
      AppLogger.info('Getting factory input schema for device type: $deviceTypeId');

      final capabilities = await getCapabilitiesForDeviceType(deviceTypeId);

      final combinedSchema = <String, dynamic>{};
      for (final cap in capabilities) {
        if (cap.hasFactoryInput) {
          combinedSchema[cap.name] = cap.factoryInputSchema;
        }
      }

      AppLogger.info(
          'Combined factory input schema has ${combinedSchema.length} capabilities');
      return combinedSchema;
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to get factory input schema for device type', error, stackTrace);
      rethrow;
    }
  }

  /// Get combined factory output schema for a device type
  ///
  /// Merges all capability factory_output_schema for the device type.
  /// Defines what data the device returns after factory provisioning.
  Future<Map<String, dynamic>> getFactoryOutputSchemaForDeviceType(
      String deviceTypeId) async {
    try {
      AppLogger.info('Getting factory output schema for device type: $deviceTypeId');

      final capabilities = await getCapabilitiesForDeviceType(deviceTypeId);

      final combinedSchema = <String, dynamic>{};
      for (final cap in capabilities) {
        if (cap.hasFactoryOutput) {
          combinedSchema[cap.name] = cap.factoryOutputSchema;
        }
      }

      AppLogger.info(
          'Combined factory output schema has ${combinedSchema.length} capabilities');
      return combinedSchema;
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to get factory output schema for device type', error, stackTrace);
      rethrow;
    }
  }

  /// Get combined consumer input schema for a device type
  ///
  /// Used by consumer provisioning apps (BLE).
  /// Also drives BLE service generation in firmware.
  Future<Map<String, dynamic>> getConsumerInputSchemaForDeviceType(
      String deviceTypeId) async {
    try {
      AppLogger.info('Getting consumer input schema for device type: $deviceTypeId');

      final capabilities = await getCapabilitiesForDeviceType(deviceTypeId);

      final combinedSchema = <String, dynamic>{};
      for (final cap in capabilities) {
        if (cap.hasConsumerInput) {
          combinedSchema[cap.name] = cap.consumerInputSchema;
        }
      }

      AppLogger.info(
          'Combined consumer input schema has ${combinedSchema.length} capabilities');
      return combinedSchema;
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to get consumer input schema for device type', error, stackTrace);
      rethrow;
    }
  }

  /// Get combined consumer output schema for a device type
  ///
  /// Merges all capability consumer_output_schema for the device type.
  /// Defines what data the device returns after consumer provisioning.
  Future<Map<String, dynamic>> getConsumerOutputSchemaForDeviceType(
      String deviceTypeId) async {
    try {
      AppLogger.info('Getting consumer output schema for device type: $deviceTypeId');

      final capabilities = await getCapabilitiesForDeviceType(deviceTypeId);

      final combinedSchema = <String, dynamic>{};
      for (final cap in capabilities) {
        if (cap.hasConsumerOutput) {
          combinedSchema[cap.name] = cap.consumerOutputSchema;
        }
      }

      AppLogger.info(
          'Combined consumer output schema has ${combinedSchema.length} capabilities');
      return combinedSchema;
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to get consumer output schema for device type', error, stackTrace);
      rethrow;
    }
  }

  /// Get combined heartbeat schema for a device type
  Future<Map<String, dynamic>> getHeartbeatSchemaForDeviceType(
      String deviceTypeId) async {
    try {
      AppLogger.info('Getting heartbeat schema for device type: $deviceTypeId');

      final capabilities = await getCapabilitiesForDeviceType(deviceTypeId);

      final combinedSchema = <String, dynamic>{};
      for (final cap in capabilities) {
        if (cap.hasHeartbeat) {
          combinedSchema[cap.name] = cap.heartbeatSchema;
        }
      }

      AppLogger.info(
          'Combined heartbeat schema has ${combinedSchema.length} capabilities');
      return combinedSchema;
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to get heartbeat schema for device type', error, stackTrace);
      rethrow;
    }
  }

  /// Get all tests available for a device type (by ID)
  Future<List<CapabilityTest>> getTestsForDeviceType(
      String deviceTypeId) async {
    try {
      AppLogger.info('Getting tests for device type: $deviceTypeId');

      final capabilities = await getCapabilitiesForDeviceType(deviceTypeId);

      final allTests = <CapabilityTest>[];
      for (final cap in capabilities) {
        allTests.addAll(cap.tests);
      }

      AppLogger.info('Found ${allTests.length} tests for device type');
      return allTests;
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to get tests for device type', error, stackTrace);
      rethrow;
    }
  }

  /// Get all tests available for a device type (by slug)
  Future<List<CapabilityTest>> getTestsForDeviceTypeBySlug(
      String deviceTypeSlug) async {
    try {
      AppLogger.info('Getting tests for device type by slug: $deviceTypeSlug');

      // First get the device type ID from slug
      final deviceTypeResponse = await _supabase
          .from('device_types')
          .select('id')
          .eq('slug', deviceTypeSlug)
          .maybeSingle();

      if (deviceTypeResponse == null) {
        AppLogger.info('Device type not found for slug: $deviceTypeSlug');
        return [];
      }

      final deviceTypeId = deviceTypeResponse['id'] as String;
      return getTestsForDeviceType(deviceTypeId);
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to get tests for device type by slug', error, stackTrace);
      rethrow;
    }
  }
}
