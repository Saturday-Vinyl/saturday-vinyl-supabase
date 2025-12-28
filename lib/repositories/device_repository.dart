import 'package:saturday_consumer_app/models/device.dart';
import 'package:saturday_consumer_app/repositories/base_repository.dart';

/// Repository for device-related database operations.
class DeviceRepository extends BaseRepository {
  static const _tableName = 'devices';

  /// Gets all devices owned by a user.
  Future<List<Device>> getUserDevices(String userId) async {
    final response = await client
        .from(_tableName)
        .select()
        .eq('user_id', userId)
        .order('created_at');

    return (response as List).map((row) => Device.fromJson(row)).toList();
  }

  /// Gets a device by ID.
  Future<Device?> getDevice(String deviceId) async {
    final response = await client
        .from(_tableName)
        .select()
        .eq('id', deviceId)
        .maybeSingle();

    if (response == null) return null;
    return Device.fromJson(response);
  }

  /// Gets a device by serial number.
  Future<Device?> getDeviceBySerial(String serialNumber) async {
    final response = await client
        .from(_tableName)
        .select()
        .eq('serial_number', serialNumber)
        .maybeSingle();

    if (response == null) return null;
    return Device.fromJson(response);
  }

  /// Creates a new device.
  Future<Device> createDevice(Device device) async {
    final response = await client
        .from(_tableName)
        .insert(device.toJson()..remove('id'))
        .select()
        .single();

    return Device.fromJson(response);
  }

  /// Updates a device.
  Future<Device> updateDevice(Device device) async {
    final response = await client
        .from(_tableName)
        .update({
          'name': device.name,
          'firmware_version': device.firmwareVersion,
          'status': device.status.toJsonString(),
          'battery_level': device.batteryLevel,
          'last_seen_at': device.lastSeenAt?.toIso8601String(),
          'settings': device.settings,
        })
        .eq('id', device.id)
        .select()
        .single();

    return Device.fromJson(response);
  }

  /// Updates a device's status.
  Future<Device> updateDeviceStatus(
      String deviceId, DeviceStatus status) async {
    final response = await client
        .from(_tableName)
        .update({
          'status': status.toJsonString(),
          'last_seen_at':
              status == DeviceStatus.online ? DateTime.now().toIso8601String() : null,
        })
        .eq('id', deviceId)
        .select()
        .single();

    return Device.fromJson(response);
  }

  /// Updates a device's battery level.
  Future<void> updateBatteryLevel(String deviceId, int level) async {
    await client.from(_tableName).update({
      'battery_level': level,
      'last_seen_at': DateTime.now().toIso8601String(),
    }).eq('id', deviceId);
  }

  /// Deletes a device.
  Future<void> deleteDevice(String deviceId) async {
    await client.from(_tableName).delete().eq('id', deviceId);
  }

  /// Gets all hubs for a user.
  Future<List<Device>> getUserHubs(String userId) async {
    final response = await client
        .from(_tableName)
        .select()
        .eq('user_id', userId)
        .eq('device_type', DeviceType.hub.name)
        .order('created_at');

    return (response as List).map((row) => Device.fromJson(row)).toList();
  }

  /// Gets all crates for a user.
  Future<List<Device>> getUserCrates(String userId) async {
    final response = await client
        .from(_tableName)
        .select()
        .eq('user_id', userId)
        .eq('device_type', DeviceType.crate.name)
        .order('created_at');

    return (response as List).map((row) => Device.fromJson(row)).toList();
  }
}
