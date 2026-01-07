import 'package:saturday_app/models/device_type.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:uuid/uuid.dart';

/// Repository for managing device types
class DeviceTypeRepository {
  final _supabase = SupabaseService.instance.client;
  final _uuid = const Uuid();

  /// Get all device types, optionally filtered by active status
  Future<List<DeviceType>> getAll({bool? isActive}) async {
    try {
      AppLogger.info('Fetching device types (isActive: $isActive)');

      final response = isActive != null
          ? await _supabase
              .from('device_types')
              .select()
              .eq('is_active', isActive)
              .order('name')
          : await _supabase.from('device_types').select().order('name');

      final deviceTypes = (response as List)
          .map((json) => DeviceType.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.info('Fetched ${deviceTypes.length} device types');
      return deviceTypes;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch device types', error, stackTrace);
      rethrow;
    }
  }

  /// Get a single device type by ID
  Future<DeviceType> getById(String id) async {
    try {
      AppLogger.info('Fetching device type: $id');

      final response =
          await _supabase.from('device_types').select().eq('id', id).single();

      final deviceType = DeviceType.fromJson(response);

      AppLogger.info('Fetched device type: ${deviceType.name}');
      return deviceType;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch device type', error, stackTrace);
      rethrow;
    }
  }

  /// Search device types by name
  Future<List<DeviceType>> search(String query) async {
    try {
      AppLogger.info('Searching device types: $query');

      final response = await _supabase
          .from('device_types')
          .select()
          .ilike('name', '%$query%')
          .order('name');

      final deviceTypes = (response as List)
          .map((json) => DeviceType.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.info('Found ${deviceTypes.length} device types');
      return deviceTypes;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to search device types', error, stackTrace);
      rethrow;
    }
  }

  /// Create a new device type
  Future<DeviceType> create(DeviceType deviceType) async {
    try {
      AppLogger.info('Creating device type: ${deviceType.name}');

      final id = _uuid.v4();
      final now = DateTime.now();

      await _supabase.from('device_types').insert({
        'id': id,
        'name': deviceType.name,
        'description': deviceType.description,
        'capabilities': deviceType.capabilities,
        'spec_url': deviceType.specUrl,
        'current_firmware_version': deviceType.currentFirmwareVersion,
        'chip_type': deviceType.chipType,
        'is_active': deviceType.isActive,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      final createdDeviceType = DeviceType(
        id: id,
        name: deviceType.name,
        description: deviceType.description,
        capabilities: deviceType.capabilities,
        specUrl: deviceType.specUrl,
        currentFirmwareVersion: deviceType.currentFirmwareVersion,
        chipType: deviceType.chipType,
        isActive: deviceType.isActive,
        createdAt: now,
        updatedAt: now,
      );

      AppLogger.info('Device type created successfully');
      return createdDeviceType;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create device type', error, stackTrace);
      rethrow;
    }
  }

  /// Update an existing device type
  Future<void> update(DeviceType deviceType) async {
    try {
      AppLogger.info('Updating device type: ${deviceType.id}');

      final now = DateTime.now();

      await _supabase.from('device_types').update({
        'name': deviceType.name,
        'description': deviceType.description,
        'capabilities': deviceType.capabilities,
        'spec_url': deviceType.specUrl,
        'current_firmware_version': deviceType.currentFirmwareVersion,
        'chip_type': deviceType.chipType,
        'is_active': deviceType.isActive,
        'updated_at': now.toIso8601String(),
      }).eq('id', deviceType.id);

      AppLogger.info('Device type updated successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update device type', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a device type
  Future<void> delete(String id) async {
    try {
      AppLogger.info('Deleting device type: $id');

      await _supabase.from('device_types').delete().eq('id', id);

      AppLogger.info('Device type deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete device type', error, stackTrace);
      rethrow;
    }
  }

  /// Get device types used in a specific product
  Future<List<DeviceType>> getForProduct(String productId) async {
    try {
      AppLogger.info('Fetching device types for product: $productId');

      final response = await _supabase
          .from('product_device_types')
          .select('device_types(*)')
          .eq('product_id', productId);

      final deviceTypes = (response as List)
          .map((item) =>
              DeviceType.fromJson(item['device_types'] as Map<String, dynamic>))
          .toList();

      AppLogger.info('Fetched ${deviceTypes.length} device types for product');
      return deviceTypes;
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to fetch device types for product', error, stackTrace);
      rethrow;
    }
  }
}
