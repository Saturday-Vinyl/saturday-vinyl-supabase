import 'dart:convert';

import 'package:saturday_consumer_app/models/consumer_attributes.dart';
import 'package:saturday_consumer_app/models/device.dart';
import 'package:saturday_consumer_app/repositories/base_repository.dart';

/// Repository for managing units and their associated devices.
///
/// This repository provides access to the unified `units` + `devices` schema,
/// replacing the legacy `consumer_devices` table operations.
class UnitRepository extends BaseRepository {
  static const _unitsTable = 'units';
  static const _devicesTable = 'devices';

  /// Gets all units owned by a user with their linked device data.
  ///
  /// Returns a list of [Device] objects constructed from the joined
  /// units + devices query.
  Future<List<Device>> getUserDevices(String userId) async {
    final response = await client
        .from(_unitsTable)
        .select('''
          *,
          devices!left(
            mac_address,
            provision_data
          )
        ''')
        .eq('consumer_user_id', userId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((row) => Device.fromJoinedJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Gets a single unit by ID with its linked device data.
  Future<Device?> getDevice(String unitId) async {
    final response = await client
        .from(_unitsTable)
        .select('''
          *,
          devices!left(
            mac_address,
            provision_data
          )
        ''')
        .eq('id', unitId)
        .maybeSingle();

    if (response == null) return null;
    return Device.fromJoinedJson(response);
  }

  /// Gets a unit by serial number with its linked device data.
  Future<Device?> getDeviceBySerial(String serialNumber) async {
    final response = await client
        .from(_unitsTable)
        .select('''
          *,
          devices!left(
            mac_address,
            provision_data
          )
        ''')
        .eq('serial_number', serialNumber)
        .maybeSingle();

    if (response == null) return null;
    return Device.fromJoinedJson(response);
  }

  /// Claims a unit by serial number for the current user.
  ///
  /// This calls the `claim-unit` Edge Function which:
  /// 1. Verifies the unit exists and is unclaimed
  /// 2. Sets the user_id on the unit
  /// 3. Updates the status to 'user_claimed'
  ///
  /// Returns the claimed device on success.
  /// Throws if the unit is not found or already claimed.
  Future<Device> claimUnit(String serialNumber) async {
    final response = await client.functions.invoke(
      'claim-unit',
      body: {'serial_number': serialNumber},
    );

    if (response.status != 200) {
      final error = response.data?['error'] ?? 'Failed to claim unit';
      throw Exception(error);
    }

    return Device.fromJoinedJson(response.data as Map<String, dynamic>);
  }

  /// Updates a unit with consumer provisioning data.
  ///
  /// This should be called after BLE provisioning is complete to:
  /// 1. Update the unit with the consumer's chosen name
  /// 2. Update the linked device with WiFi/Thread credentials (provision_data)
  ///    and consumer provisioning timestamps
  ///
  /// The provision_data column on the devices table uses a flattened JSONB structure:
  /// - For hubs: { "wifi_ssid": "MyNetwork" }
  /// - For crates: { "thread_dataset": "...", "thread_network_name": "..." }
  ///
  /// Note: provision_data is MERGED with existing data, not overwritten.
  Future<Device> updateUnitProvisioning({
    required String unitId,
    required String userId,
    required String deviceName,
    required ProvisionData provisionData,
  }) async {
    // Step 1: Update the unit with consumer-specific data
    final unitResponse = await client
        .from(_unitsTable)
        .update({
          'consumer_name': deviceName,
          'status': 'claimed',
        })
        .eq('id', unitId)
        .select('''
          *,
          devices!left(
            mac_address,
            provision_data
          )
        ''')
        .single();

    // Step 2: If there's a linked device, update it with provision data and timestamps
    final devicesList = unitResponse['devices'] as List<dynamic>?;
    if (devicesList != null && devicesList.isNotEmpty) {
      final deviceData = devicesList.first as Map<String, dynamic>?;
      if (deviceData != null && deviceData['id'] != null) {
        final deviceId = deviceData['id'] as String;
        final newProvisionData = provisionData.toJson();

        // Merge with existing provision_data instead of overwriting
        final existingProvisionData =
            deviceData['provision_data'] as Map<String, dynamic>? ?? {};
        final mergedProvisionData = {
          ...existingProvisionData,
          ...newProvisionData,
        };

        // Update device with merged provision_data and consumer provisioning info
        await client.from(_devicesTable).update({
          'provision_data': mergedProvisionData,
          'consumer_provisioned_at': DateTime.now().toIso8601String(),
          'consumer_provisioned_by': userId,
        }).eq('id', deviceId);
      }
    }

    // Return the updated device (re-fetch to get latest data)
    final response = await client
        .from(_unitsTable)
        .select('''
          *,
          devices!left(
            mac_address,
            provision_data
          )
        ''')
        .eq('id', unitId)
        .single();

    return Device.fromJoinedJson(response);
  }

  /// Updates the consumer name for a unit.
  Future<void> updateDeviceName(String unitId, String name) async {
    await client.from(_unitsTable).update({'consumer_name': name}).eq('id', unitId);
  }

  /// Unclaims a unit, releasing it back to factory state.
  ///
  /// This calls the `unclaim-unit` Edge Function which:
  /// 1. Verifies the current user owns the unit
  /// 2. Clears user_id, device_name, consumer_provisioned_at on the unit
  /// 3. Clears provision_data on the linked device
  /// 4. Updates unit status to 'factory_provisioned'
  Future<void> unclaimUnit(String unitId) async {
    final response = await client.functions.invoke(
      'unclaim-unit',
      body: {'unit_id': unitId},
    );

    if (response.status != 200) {
      final error = response.data?['error'] ?? 'Failed to unclaim unit';
      throw Exception(error);
    }
  }

  /// Gets all hubs owned by a user.
  Future<List<Device>> getUserHubs(String userId) async {
    final devices = await getUserDevices(userId);
    return devices.where((d) => d.isHub).toList();
  }

  /// Gets all crates owned by a user.
  Future<List<Device>> getUserCrates(String userId) async {
    final devices = await getUserDevices(userId);
    return devices.where((d) => d.isCrate).toList();
  }

  /// Gets the primary (first online) hub for a user.
  ///
  /// Used for crate provisioning to get Thread credentials.
  Future<Device?> getPrimaryHub(String userId) async {
    final hubs = await getUserHubs(userId);
    // Prefer online hubs
    final onlineHubs = hubs.where((h) => h.isEffectivelyOnline).toList();
    if (onlineHubs.isNotEmpty) return onlineHubs.first;
    // Fall back to any hub
    return hubs.isNotEmpty ? hubs.first : null;
  }

  /// Gets the Thread credentials from a hub's linked device provision data.
  ///
  /// This is used during crate provisioning to get the Thread network
  /// credentials from a provisioned hub. The Hub stores Thread credentials
  /// in `devices.provision_data.thread_credentials` (set during factory
  /// provisioning). The returned JSON string is written directly to the
  /// Crate's Thread Dataset BLE characteristic.
  Future<String?> getHubThreadDataset(String hubUnitId) async {
    // Query the unit with its linked device to get provision_data
    final response = await client
        .from(_unitsTable)
        .select('''
          devices!left(
            provision_data
          )
        ''')
        .eq('id', hubUnitId)
        .maybeSingle();

    if (response == null) return null;

    // Extract provision_data from the linked device
    final devicesList = response['devices'] as List<dynamic>?;
    if (devicesList == null || devicesList.isEmpty) return null;

    final deviceData = devicesList.first as Map<String, dynamic>?;
    if (deviceData == null) return null;

    final data = deviceData['provision_data'] as Map<String, dynamic>?;
    if (data == null) return null;

    // Thread credentials are stored under 'thread_credentials' key
    // (set during factory provisioning of the Hub)
    final threadCreds = data['thread_credentials'] as Map<String, dynamic>?;
    if (threadCreds == null) return null;

    // The Crate firmware's consumer_input schema expects the wrapping object:
    // { "thread_credentials": { "pan_id", "channel", "network_key", ... } }
    return jsonEncode({'thread_credentials': threadCreds});
  }
}
