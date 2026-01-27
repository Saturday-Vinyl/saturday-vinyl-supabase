import 'package:saturday_app/models/device.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Repository for managing devices (hardware instances identified by MAC address)
///
/// A device represents a physical PCB with its own MAC address. A unit can
/// contain multiple devices (e.g., a Crate has ESP32-S3 + ESP32-H2 chips).
class DeviceRepository {
  final _supabase = SupabaseService.instance.client;

  // ============================================================================
  // Device Creation
  // ============================================================================

  /// Create a new device record
  ///
  /// Called during factory provisioning when a device first reports its MAC address.
  Future<Device> createDevice({
    required String macAddress,
    required String deviceTypeId,
    String? unitId,
    String? firmwareVersion,
    String? firmwareId,
  }) async {
    try {
      AppLogger.info('Creating device with MAC: $macAddress');

      // Validate MAC address format
      if (!Device.validateMacAddress(macAddress)) {
        throw ArgumentError('Invalid MAC address format: $macAddress');
      }

      final deviceData = {
        'mac_address': macAddress,
        'device_type_id': deviceTypeId,
        'unit_id': unitId,
        'firmware_version': firmwareVersion,
        'firmware_id': firmwareId,
        'status': DeviceStatus.unprovisioned.databaseValue,
      };

      final response = await _supabase
          .from('devices')
          .insert(deviceData)
          .select()
          .single();

      final device = Device.fromJson(response);
      AppLogger.info('Device created successfully: ${device.macAddress}');
      return device;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create device', error, stackTrace);
      rethrow;
    }
  }

  /// Create or update a device (upsert by MAC address)
  ///
  /// This is useful when a device reports in and we don't know if it already exists.
  Future<Device> upsertDevice({
    required String macAddress,
    required String deviceTypeId,
    String? unitId,
    String? firmwareVersion,
    String? firmwareId,
  }) async {
    try {
      AppLogger.info('Upserting device with MAC: $macAddress');

      if (!Device.validateMacAddress(macAddress)) {
        throw ArgumentError('Invalid MAC address format: $macAddress');
      }

      final deviceData = {
        'mac_address': macAddress,
        'device_type_id': deviceTypeId,
        if (unitId != null) 'unit_id': unitId,
        if (firmwareVersion != null) 'firmware_version': firmwareVersion,
        if (firmwareId != null) 'firmware_id': firmwareId,
      };

      final response = await _supabase
          .from('devices')
          .upsert(deviceData, onConflict: 'mac_address')
          .select()
          .single();

      final device = Device.fromJson(response);
      AppLogger.info('Device upserted: ${device.macAddress}');
      return device;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to upsert device', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Device Retrieval
  // ============================================================================

  /// Get a device by its database ID
  Future<Device> getDeviceById(String id) async {
    try {
      AppLogger.info('Fetching device by ID: $id');

      final response =
          await _supabase.from('devices').select().eq('id', id).single();

      final device = Device.fromJson(response);
      return device;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch device by ID', error, stackTrace);
      rethrow;
    }
  }

  /// Get a device by its MAC address
  Future<Device?> getDeviceByMacAddress(String macAddress) async {
    try {
      AppLogger.info('Fetching device by MAC: $macAddress');

      final response = await _supabase
          .from('devices')
          .select()
          .eq('mac_address', macAddress)
          .maybeSingle();

      if (response == null) {
        AppLogger.info('No device found with MAC: $macAddress');
        return null;
      }

      final device = Device.fromJson(response);
      AppLogger.info('Found device: ${device.macAddress}');
      return device;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch device by MAC', error, stackTrace);
      rethrow;
    }
  }

  /// Get all devices for a unit
  Future<List<Device>> getDevicesForUnit(String unitId) async {
    try {
      AppLogger.info('Fetching devices for unit: $unitId');

      final response = await _supabase
          .from('devices')
          .select()
          .eq('unit_id', unitId)
          .order('created_at', ascending: true);

      final devices =
          (response as List).map((json) => Device.fromJson(json)).toList();

      AppLogger.info('Found ${devices.length} devices for unit $unitId');
      return devices;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch devices for unit', error, stackTrace);
      rethrow;
    }
  }

  /// Get all devices of a specific device type
  Future<List<Device>> getDevicesByType(String deviceTypeId) async {
    try {
      AppLogger.info('Fetching devices by type: $deviceTypeId');

      final response = await _supabase
          .from('devices')
          .select()
          .eq('device_type_id', deviceTypeId)
          .order('created_at', ascending: false);

      final devices =
          (response as List).map((json) => Device.fromJson(json)).toList();

      AppLogger.info('Found ${devices.length} devices of type $deviceTypeId');
      return devices;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch devices by type', error, stackTrace);
      rethrow;
    }
  }

  /// Get all online devices
  Future<List<Device>> getOnlineDevices() async {
    try {
      AppLogger.info('Fetching online devices');

      // Devices are online if last_seen_at is within 60 seconds
      final threshold =
          DateTime.now().subtract(const Duration(seconds: 60)).toIso8601String();

      final response = await _supabase
          .from('devices')
          .select()
          .gte('last_seen_at', threshold)
          .order('last_seen_at', ascending: false);

      final devices =
          (response as List).map((json) => Device.fromJson(json)).toList();

      AppLogger.info('Found ${devices.length} online devices');
      return devices;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch online devices', error, stackTrace);
      rethrow;
    }
  }

  /// Get devices by status
  Future<List<Device>> getDevicesByStatus(DeviceStatus status) async {
    try {
      AppLogger.info('Fetching devices with status: ${status.databaseValue}');

      final response = await _supabase
          .from('devices')
          .select()
          .eq('status', status.databaseValue)
          .order('created_at', ascending: false);

      final devices =
          (response as List).map((json) => Device.fromJson(json)).toList();

      AppLogger.info('Found ${devices.length} devices with status $status');
      return devices;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch devices by status', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Factory Provisioning
  // ============================================================================

  /// Mark device as factory provisioned
  ///
  /// Called after successful factory provisioning via Service Mode.
  Future<Device> markFactoryProvisioned({
    required String deviceId,
    required String userId,
    Map<String, dynamic>? factoryAttributes,
  }) async {
    try {
      AppLogger.info('Marking device as factory provisioned: $deviceId');

      final updateData = {
        'status': DeviceStatus.provisioned.databaseValue,
        'factory_provisioned_at': DateTime.now().toIso8601String(),
        'factory_provisioned_by': userId,
        if (factoryAttributes != null) 'factory_attributes': factoryAttributes,
      };

      final response = await _supabase
          .from('devices')
          .update(updateData)
          .eq('id', deviceId)
          .select()
          .single();

      final device = Device.fromJson(response);
      AppLogger.info('Device marked as factory provisioned');
      return device;
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to mark device as factory provisioned', error, stackTrace);
      rethrow;
    }
  }

  /// Update factory attributes for a device
  Future<Device> updateFactoryAttributes({
    required String deviceId,
    required Map<String, dynamic> attributes,
  }) async {
    try {
      AppLogger.info('Updating factory attributes for device: $deviceId');

      final response = await _supabase
          .from('devices')
          .update({'factory_attributes': attributes})
          .eq('id', deviceId)
          .select()
          .single();

      final device = Device.fromJson(response);
      AppLogger.info('Factory attributes updated');
      return device;
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to update factory attributes', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Firmware Tracking
  // ============================================================================

  /// Update firmware version for a device
  Future<Device> updateFirmware({
    required String deviceId,
    required String firmwareVersion,
    String? firmwareId,
  }) async {
    try {
      AppLogger.info('Updating firmware for device $deviceId to $firmwareVersion');

      final updateData = {
        'firmware_version': firmwareVersion,
        if (firmwareId != null) 'firmware_id': firmwareId,
      };

      final response = await _supabase
          .from('devices')
          .update(updateData)
          .eq('id', deviceId)
          .select()
          .single();

      final device = Device.fromJson(response);
      AppLogger.info('Firmware updated successfully');
      return device;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update firmware', error, stackTrace);
      rethrow;
    }
  }

  /// Get devices with specific firmware version
  Future<List<Device>> getDevicesWithFirmware(String firmwareId) async {
    try {
      AppLogger.info('Fetching devices with firmware: $firmwareId');

      final response = await _supabase
          .from('devices')
          .select()
          .eq('firmware_id', firmwareId)
          .order('created_at', ascending: false);

      final devices =
          (response as List).map((json) => Device.fromJson(json)).toList();

      AppLogger.info('Found ${devices.length} devices with firmware $firmwareId');
      return devices;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch devices with firmware', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Connectivity Tracking
  // ============================================================================

  /// Update last seen timestamp for a device
  ///
  /// Called when a heartbeat is received from the device.
  Future<Device> updateLastSeen(String deviceId) async {
    try {
      AppLogger.info('Updating last seen for device: $deviceId');

      final response = await _supabase
          .from('devices')
          .update({
            'last_seen_at': DateTime.now().toIso8601String(),
            'status': DeviceStatus.online.databaseValue,
          })
          .eq('id', deviceId)
          .select()
          .single();

      final device = Device.fromJson(response);
      AppLogger.info('Last seen updated');
      return device;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update last seen', error, stackTrace);
      rethrow;
    }
  }

  /// Update last seen by MAC address
  ///
  /// Convenience method when processing heartbeats by MAC address.
  Future<Device?> updateLastSeenByMac(String macAddress) async {
    try {
      AppLogger.info('Updating last seen by MAC: $macAddress');

      final response = await _supabase
          .from('devices')
          .update({
            'last_seen_at': DateTime.now().toIso8601String(),
            'status': DeviceStatus.online.databaseValue,
          })
          .eq('mac_address', macAddress)
          .select()
          .maybeSingle();

      if (response == null) {
        AppLogger.info('No device found with MAC: $macAddress');
        return null;
      }

      final device = Device.fromJson(response);
      AppLogger.info('Last seen updated for ${device.macAddress}');
      return device;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update last seen by MAC', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Unit Assignment
  // ============================================================================

  /// Assign device to a unit
  Future<Device> assignToUnit({
    required String deviceId,
    required String unitId,
  }) async {
    try {
      AppLogger.info('Assigning device $deviceId to unit $unitId');

      final response = await _supabase
          .from('devices')
          .update({'unit_id': unitId})
          .eq('id', deviceId)
          .select()
          .single();

      final device = Device.fromJson(response);
      AppLogger.info('Device assigned to unit');
      return device;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to assign device to unit', error, stackTrace);
      rethrow;
    }
  }

  /// Assign device to unit by MAC address
  Future<Device?> assignToUnitByMac({
    required String macAddress,
    required String unitId,
  }) async {
    try {
      AppLogger.info('Assigning device $macAddress to unit $unitId');

      final response = await _supabase
          .from('devices')
          .update({'unit_id': unitId})
          .eq('mac_address', macAddress)
          .select()
          .maybeSingle();

      if (response == null) {
        AppLogger.info('No device found with MAC: $macAddress');
        return null;
      }

      final device = Device.fromJson(response);
      AppLogger.info('Device assigned to unit');
      return device;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to assign device to unit by MAC', error, stackTrace);
      rethrow;
    }
  }

  /// Unassign device from its unit
  Future<Device> unassignFromUnit(String deviceId) async {
    try {
      AppLogger.info('Unassigning device from unit: $deviceId');

      final response = await _supabase
          .from('devices')
          .update({'unit_id': null})
          .eq('id', deviceId)
          .select()
          .single();

      final device = Device.fromJson(response);
      AppLogger.info('Device unassigned from unit');
      return device;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to unassign device from unit', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Device Deletion
  // ============================================================================

  /// Delete a device
  Future<void> deleteDevice(String deviceId) async {
    try {
      AppLogger.info('Deleting device: $deviceId');

      await _supabase.from('devices').delete().eq('id', deviceId);

      AppLogger.info('Device deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete device', error, stackTrace);
      rethrow;
    }
  }

  /// Delete device by MAC address
  Future<void> deleteDeviceByMac(String macAddress) async {
    try {
      AppLogger.info('Deleting device by MAC: $macAddress');

      await _supabase.from('devices').delete().eq('mac_address', macAddress);

      AppLogger.info('Device deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete device by MAC', error, stackTrace);
      rethrow;
    }
  }
}
