import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/device.dart';
import 'package:saturday_app/repositories/device_repository.dart';

/// Provider for DeviceRepository singleton
final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  return DeviceRepository();
});

/// Provider for devices by unit
final devicesByUnitProvider =
    FutureProvider.family<List<Device>, String>((ref, unitId) async {
  final repository = ref.watch(deviceRepositoryProvider);
  return repository.getDevicesForUnit(unitId);
});

/// Provider for devices by device type
final devicesByTypeProvider =
    FutureProvider.family<List<Device>, String>((ref, deviceTypeId) async {
  final repository = ref.watch(deviceRepositoryProvider);
  return repository.getDevicesByType(deviceTypeId);
});

/// Provider for devices by status
final devicesByStatusProvider =
    FutureProvider.family<List<Device>, DeviceStatus>((ref, status) async {
  final repository = ref.watch(deviceRepositoryProvider);
  return repository.getDevicesByStatus(status);
});

/// Provider for online devices
final onlineDevicesProvider = FutureProvider<List<Device>>((ref) async {
  final repository = ref.watch(deviceRepositoryProvider);
  return repository.getOnlineDevices();
});

/// Provider for a single device by ID
final deviceByIdProvider =
    FutureProvider.family<Device, String>((ref, id) async {
  final repository = ref.watch(deviceRepositoryProvider);
  return repository.getDeviceById(id);
});

/// Provider for a single device by MAC address
final deviceByMacProvider =
    FutureProvider.family<Device?, String>((ref, macAddress) async {
  final repository = ref.watch(deviceRepositoryProvider);
  return repository.getDeviceByMacAddress(macAddress);
});

/// Provider for devices with specific firmware
final devicesWithFirmwareProvider =
    FutureProvider.family<List<Device>, String>((ref, firmwareId) async {
  final repository = ref.watch(deviceRepositoryProvider);
  return repository.getDevicesWithFirmware(firmwareId);
});

/// Provider for device management actions
final deviceManagementProvider = Provider<DeviceManagement>((ref) {
  return DeviceManagement(ref);
});

/// Class for managing device actions
class DeviceManagement {
  final Ref ref;

  DeviceManagement(this.ref);

  /// Create a new device
  Future<Device> createDevice({
    required String macAddress,
    required String deviceTypeId,
    String? unitId,
    String? firmwareVersion,
    String? firmwareId,
  }) async {
    final repository = ref.read(deviceRepositoryProvider);
    final device = await repository.createDevice(
      macAddress: macAddress,
      deviceTypeId: deviceTypeId,
      unitId: unitId,
      firmwareVersion: firmwareVersion,
      firmwareId: firmwareId,
    );

    // Invalidate relevant providers
    ref.invalidate(devicesByTypeProvider(deviceTypeId));
    if (unitId != null) {
      ref.invalidate(devicesByUnitProvider(unitId));
    }
    ref.invalidate(devicesByStatusProvider(DeviceStatus.unprovisioned));

    return device;
  }

  /// Create or update a device (upsert by MAC address)
  Future<Device> upsertDevice({
    required String macAddress,
    required String deviceTypeId,
    String? unitId,
    String? firmwareVersion,
    String? firmwareId,
  }) async {
    final repository = ref.read(deviceRepositoryProvider);
    final device = await repository.upsertDevice(
      macAddress: macAddress,
      deviceTypeId: deviceTypeId,
      unitId: unitId,
      firmwareVersion: firmwareVersion,
      firmwareId: firmwareId,
    );

    // Invalidate relevant providers
    ref.invalidate(deviceByMacProvider(macAddress));
    ref.invalidate(devicesByTypeProvider(deviceTypeId));
    if (unitId != null) {
      ref.invalidate(devicesByUnitProvider(unitId));
    }

    return device;
  }

  /// Mark device as factory provisioned
  Future<Device> markFactoryProvisioned({
    required String deviceId,
    required String userId,
    Map<String, dynamic>? factoryAttributes,
  }) async {
    final repository = ref.read(deviceRepositoryProvider);
    final device = await repository.markFactoryProvisioned(
      deviceId: deviceId,
      userId: userId,
      factoryAttributes: factoryAttributes,
    );

    ref.invalidate(deviceByIdProvider(deviceId));
    ref.invalidate(devicesByStatusProvider(DeviceStatus.unprovisioned));
    ref.invalidate(devicesByStatusProvider(DeviceStatus.provisioned));

    return device;
  }

  /// Update factory attributes
  Future<Device> updateFactoryAttributes({
    required String deviceId,
    required Map<String, dynamic> attributes,
  }) async {
    final repository = ref.read(deviceRepositoryProvider);
    final device = await repository.updateFactoryAttributes(
      deviceId: deviceId,
      attributes: attributes,
    );

    ref.invalidate(deviceByIdProvider(deviceId));
    return device;
  }

  /// Update firmware version
  Future<Device> updateFirmware({
    required String deviceId,
    required String firmwareVersion,
    String? firmwareId,
  }) async {
    final repository = ref.read(deviceRepositoryProvider);
    final device = await repository.updateFirmware(
      deviceId: deviceId,
      firmwareVersion: firmwareVersion,
      firmwareId: firmwareId,
    );

    ref.invalidate(deviceByIdProvider(deviceId));
    if (firmwareId != null) {
      ref.invalidate(devicesWithFirmwareProvider(firmwareId));
    }

    return device;
  }

  /// Update last seen timestamp
  Future<Device> updateLastSeen(String deviceId) async {
    final repository = ref.read(deviceRepositoryProvider);
    final device = await repository.updateLastSeen(deviceId);

    ref.invalidate(deviceByIdProvider(deviceId));
    ref.invalidate(onlineDevicesProvider);

    return device;
  }

  /// Update last seen by MAC address
  Future<Device?> updateLastSeenByMac(String macAddress) async {
    final repository = ref.read(deviceRepositoryProvider);
    final device = await repository.updateLastSeenByMac(macAddress);

    if (device != null) {
      ref.invalidate(deviceByMacProvider(macAddress));
      ref.invalidate(onlineDevicesProvider);
    }

    return device;
  }

  /// Assign device to unit
  Future<Device> assignToUnit({
    required String deviceId,
    required String unitId,
  }) async {
    final repository = ref.read(deviceRepositoryProvider);
    final device = await repository.assignToUnit(
      deviceId: deviceId,
      unitId: unitId,
    );

    ref.invalidate(deviceByIdProvider(deviceId));
    ref.invalidate(devicesByUnitProvider(unitId));

    return device;
  }

  /// Assign device to unit by MAC address
  Future<Device?> assignToUnitByMac({
    required String macAddress,
    required String unitId,
  }) async {
    final repository = ref.read(deviceRepositoryProvider);
    final device = await repository.assignToUnitByMac(
      macAddress: macAddress,
      unitId: unitId,
    );

    if (device != null) {
      ref.invalidate(deviceByMacProvider(macAddress));
      ref.invalidate(devicesByUnitProvider(unitId));
    }

    return device;
  }

  /// Unassign device from unit
  Future<Device> unassignFromUnit(String deviceId) async {
    final repository = ref.read(deviceRepositoryProvider);

    // Get current device to know which unit to invalidate
    final currentDevice = await repository.getDeviceById(deviceId);
    final unitId = currentDevice.unitId;

    final device = await repository.unassignFromUnit(deviceId);

    ref.invalidate(deviceByIdProvider(deviceId));
    if (unitId != null) {
      ref.invalidate(devicesByUnitProvider(unitId));
    }

    return device;
  }

  /// Delete a device
  Future<void> deleteDevice(String deviceId) async {
    final repository = ref.read(deviceRepositoryProvider);

    // Get device info before deletion
    final device = await repository.getDeviceById(deviceId);

    await repository.deleteDevice(deviceId);

    // Invalidate relevant providers
    ref.invalidate(devicesByTypeProvider(device.deviceTypeId!));
    if (device.unitId != null) {
      ref.invalidate(devicesByUnitProvider(device.unitId!));
    }
    ref.invalidate(devicesByStatusProvider(device.status));
  }

  /// Delete device by MAC address
  Future<void> deleteDeviceByMac(String macAddress) async {
    final repository = ref.read(deviceRepositoryProvider);

    // Get device info before deletion
    final device = await repository.getDeviceByMacAddress(macAddress);

    await repository.deleteDeviceByMac(macAddress);

    if (device != null) {
      ref.invalidate(deviceByMacProvider(macAddress));
      if (device.deviceTypeId != null) {
        ref.invalidate(devicesByTypeProvider(device.deviceTypeId!));
      }
      if (device.unitId != null) {
        ref.invalidate(devicesByUnitProvider(device.unitId!));
      }
    }
  }
}
