import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/device_type.dart';
import 'package:saturday_app/models/product_device_type.dart';
import 'package:saturday_app/repositories/device_type_repository.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Provider for DeviceTypeRepository
final deviceTypeRepositoryProvider = Provider<DeviceTypeRepository>((ref) {
  return DeviceTypeRepository();
});

/// Provider for all device types
final deviceTypesProvider = FutureProvider<List<DeviceType>>((ref) async {
  final repository = ref.watch(deviceTypeRepositoryProvider);
  return await repository.getAll();
});

/// Provider for active device types only
final activeDeviceTypesProvider = FutureProvider<List<DeviceType>>((ref) async {
  final repository = ref.watch(deviceTypeRepositoryProvider);
  return await repository.getAll(isActive: true);
});

/// Provider for a single device type by ID (family provider)
final deviceTypeProvider =
    FutureProvider.family<DeviceType, String>((ref, id) async {
  final repository = ref.watch(deviceTypeRepositoryProvider);
  return await repository.getById(id);
});

/// Provider for a single device type by slug (family provider)
final deviceTypeBySlugProvider =
    FutureProvider.family<DeviceType?, String>((ref, slug) async {
  final repository = ref.watch(deviceTypeRepositoryProvider);
  try {
    return await repository.getBySlug(slug);
  } catch (e) {
    // Return null if not found
    return null;
  }
});

/// Provider for device type management actions
final deviceTypeManagementProvider =
    Provider((ref) => DeviceTypeManagement(ref));

/// Device type management actions
class DeviceTypeManagement {
  final Ref ref;

  DeviceTypeManagement(this.ref);

  /// Create a new device type
  Future<DeviceType> createDeviceType(DeviceType deviceType) async {
    try {
      final repository = ref.read(deviceTypeRepositoryProvider);
      final createdDeviceType = await repository.create(deviceType);

      // Invalidate the device types list to refresh
      ref.invalidate(deviceTypesProvider);
      ref.invalidate(activeDeviceTypesProvider);

      AppLogger.info('Device type created successfully');
      return createdDeviceType;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create device type', error, stackTrace);
      rethrow;
    }
  }

  /// Update an existing device type
  Future<void> updateDeviceType(DeviceType deviceType) async {
    try {
      final repository = ref.read(deviceTypeRepositoryProvider);
      await repository.update(deviceType);

      // Invalidate providers to refresh
      ref.invalidate(deviceTypesProvider);
      ref.invalidate(activeDeviceTypesProvider);
      ref.invalidate(deviceTypeProvider(deviceType.id));

      AppLogger.info('Device type updated successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update device type', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a device type
  Future<void> deleteDeviceType(String id) async {
    try {
      final repository = ref.read(deviceTypeRepositoryProvider);
      await repository.delete(id);

      // Invalidate providers to refresh
      ref.invalidate(deviceTypesProvider);
      ref.invalidate(activeDeviceTypesProvider);

      AppLogger.info('Device type deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete device type', error, stackTrace);
      rethrow;
    }
  }

  /// Search device types
  Future<List<DeviceType>> searchDeviceTypes(String query) async {
    try {
      final repository = ref.read(deviceTypeRepositoryProvider);
      return await repository.search(query);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to search device types', error, stackTrace);
      rethrow;
    }
  }

  /// Set device types for a product (replaces existing assignments)
  Future<void> setDeviceTypesForProduct({
    required String productId,
    required List<ProductDeviceType> deviceTypes,
  }) async {
    try {
      final repository = ref.read(deviceTypeRepositoryProvider);
      await repository.setDeviceTypesForProduct(
        productId: productId,
        deviceTypes: deviceTypes,
      );

      // Invalidate provider to refresh
      ref.invalidate(productDeviceTypesProvider(productId));

      AppLogger.info('Device types set for product successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to set device types for product', error, stackTrace);
      rethrow;
    }
  }
}

/// Model combining DeviceType with quantity for product assignment
class ProductDeviceTypeWithDetails {
  final DeviceType deviceType;
  final int quantity;

  const ProductDeviceTypeWithDetails({
    required this.deviceType,
    required this.quantity,
  });
}

/// Provider for device types assigned to a product (with quantities)
final productDeviceTypesProvider = FutureProvider.family<
    List<ProductDeviceTypeWithDetails>, String>((ref, productId) async {
  final repository = ref.watch(deviceTypeRepositoryProvider);
  return await repository.getDeviceTypesForProduct(productId);
});
