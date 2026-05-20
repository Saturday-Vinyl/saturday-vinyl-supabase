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
  static const _latestCrateInventoryView = 'latest_crate_inventory';

  /// Looks up the latest RFID inventory snapshot for the given crate MAC
  /// addresses and returns a map of MAC → epc_count. Empty input returns {}.
  Future<Map<String, int>> _getLatestInventoryByMac(
      Iterable<String> macAddresses) async {
    final macs = macAddresses.toList();
    if (macs.isEmpty) return const {};

    final response = await client
        .from(_latestCrateInventoryView)
        .select('mac_address, epc_count')
        .inFilter('mac_address', macs);

    return {
      for (final row in response as List)
        (row as Map<String, dynamic>)['mac_address'] as String:
            (row['epc_count'] as int? ?? 0),
    };
  }

  /// Returns a copy of [device] with [Device.currentRecordCount] populated
  /// from [inventory] (keyed by MAC). No-op for non-crate devices or when
  /// no snapshot is available.
  Device _withInventory(Device device, Map<String, int> inventory) {
    if (!device.isCrate || device.macAddress == null) return device;
    final count = inventory[device.macAddress];
    if (count == null) return device;
    return device.copyWith(currentRecordCount: count);
  }

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
          ),
          product_variants!left(
            sku,
            product_id,
            max_slots,
            products!inner(
              shopify_product_handle
            )
          )
        ''')
        .eq('consumer_user_id', userId)
        .order('created_at', ascending: false);

    final devices = (response as List)
        .map((row) => Device.fromJoinedJson(row as Map<String, dynamic>))
        .toList();

    final crateMacs = devices
        .where((d) => d.isCrate && d.macAddress != null)
        .map((d) => d.macAddress!);
    final inventory = await _getLatestInventoryByMac(crateMacs);
    if (inventory.isEmpty) return devices;
    return devices.map((d) => _withInventory(d, inventory)).toList();
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
          ),
          product_variants!left(
            sku,
            product_id,
            max_slots,
            products!inner(
              shopify_product_handle
            )
          )
        ''')
        .eq('id', unitId)
        .maybeSingle();

    if (response == null) return null;
    final device = Device.fromJoinedJson(response);
    if (!device.isCrate || device.macAddress == null) return device;
    final inventory = await _getLatestInventoryByMac([device.macAddress!]);
    return _withInventory(device, inventory);
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
          ),
          product_variants!left(
            sku,
            product_id,
            max_slots,
            products!inner(
              shopify_product_handle
            )
          )
        ''')
        .eq('serial_number', serialNumber)
        .maybeSingle();

    if (response == null) return null;
    final device = Device.fromJoinedJson(response);
    if (!device.isCrate || device.macAddress == null) return device;
    final inventory = await _getLatestInventoryByMac([device.macAddress!]);
    return _withInventory(device, inventory);
  }

  /// Adopts a non-Hub device (typically a Crate) into the current user's account.
  ///
  /// Calls the `adopt_device` Edge Function which:
  /// 1. Verifies the device exists and is either unclaimed or already owned
  ///    by the current user (idempotent re-adoption).
  /// 2. Sets `consumer_user_id` on the unit and marks status `claimed`.
  /// 3. Stamps `consumer_provisioned_at` / `consumer_provisioned_by` on the
  ///    linked device row.
  /// 4. Ensures a `thread_networks` row exists for the user.
  ///
  /// Returns the adopted [Device] on success. Throws if the device is owned
  /// by another user, not provisioned, or the cloud is unreachable.
  ///
  /// For Hub adoption, do NOT call this from the app — the Hub's BLE flow
  /// invokes `adopt_device` server-side via the User Token characteristic.
  Future<Device> adoptDevice(String serialNumber) async {
    final response = await client.functions.invoke(
      'adopt_device',
      body: {'serial_number': serialNumber},
    );

    if (response.status != 200) {
      final error = response.data?['error'] ?? 'Failed to adopt device';
      throw Exception(error);
    }

    // adopt_device returns a slim `{ id, serial_number, status }` payload —
    // not the full joined unit row that Device.fromJoinedJson expects. Fetch
    // the canonical row so callers get a fully-populated Device.
    //
    // TODO(saturday-supabase): have `adopt_device` return the full joined
    // unit row (matching the old `claim-unit` shape). Once that lands, drop
    // this follow-up fetch and parse the response directly.
    final device = await getDeviceBySerial(serialNumber);
    if (device == null) {
      throw Exception('Adopted device not found after claim: $serialNumber');
    }
    return device;
  }

  /// Fetches the user's Thread network credentials from the cloud.
  ///
  /// The returned JSON is shaped for writing directly to a Crate's Thread
  /// Dataset BLE characteristic (0x0020):
  ///
  /// ```
  /// { "thread_credentials": { "pan_id": ..., "channel": ..., ... } }
  /// ```
  ///
  /// Returns `null` if the user has not yet adopted any Hub (HTTP 404
  /// `no_thread_network`). Throws on other transport/cloud errors.
  Future<String?> getThreadCredentials() async {
    final response = await client.functions.invoke('get_thread_credentials');

    if (response.status == 404) return null;
    if (response.status != 200) {
      final error = response.data?['error'] ?? 'Failed to fetch Thread credentials';
      throw Exception(error);
    }

    final data = response.data as Map<String, dynamic>;
    final creds = data['thread_credentials'] as Map<String, dynamic>?;
    if (creds == null) return null;
    return jsonEncode({'thread_credentials': creds});
  }

  /// Persists the consumer-chosen device name and merges any user-supplied
  /// [provisionData] into the linked device's `provision_data` JSONB.
  ///
  /// This is called after BLE provisioning to set fields the cloud doesn't
  /// own — specifically `consumer_name` on the unit and the Hub's WiFi SSID
  /// in `provision_data` (used for display in the device detail screen).
  ///
  /// `consumer_provisioned_at` / `consumer_provisioned_by` are stamped
  /// server-side by `adopt_device`; do not write them from the app.
  ///
  /// Note: provision_data is MERGED with existing data, not overwritten.
  Future<Device> updateUnitProvisioning({
    required String unitId,
    required String deviceName,
    ProvisionData? provisionData,
  }) async {
    // Step 1: Update the unit with consumer-specific data
    final unitResponse = await client
        .from(_unitsTable)
        .update({'consumer_name': deviceName})
        .eq('id', unitId)
        .select('''
          *,
          devices!left(
            mac_address,
            provision_data
          ),
          product_variants!left(
            sku,
            product_id,
            max_slots,
            products!inner(
              shopify_product_handle
            )
          )
        ''')
        .single();

    // Step 2: If there's a linked device and we have provision data to write,
    // merge it into the existing JSONB.
    if (provisionData != null) {
      final devicesList = unitResponse['devices'] as List<dynamic>?;
      if (devicesList != null && devicesList.isNotEmpty) {
        final deviceData = devicesList.first as Map<String, dynamic>?;
        if (deviceData != null && deviceData['id'] != null) {
          final deviceId = deviceData['id'] as String;
          final newProvisionData = provisionData.toJson();
          if (newProvisionData.isNotEmpty) {
            final existingProvisionData =
                deviceData['provision_data'] as Map<String, dynamic>? ?? {};
            final mergedProvisionData = {
              ...existingProvisionData,
              ...newProvisionData,
            };
            await client.from(_devicesTable).update({
              'provision_data': mergedProvisionData,
            }).eq('id', deviceId);
          }
        }
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
          ),
          product_variants!left(
            sku,
            product_id,
            max_slots,
            products!inner(
              shopify_product_handle
            )
          )
        ''')
        .eq('id', unitId)
        .single();

    final device = Device.fromJoinedJson(response);
    if (!device.isCrate || device.macAddress == null) return device;
    final inventory = await _getLatestInventoryByMac([device.macAddress!]);
    return _withInventory(device, inventory);
  }

  /// Updates the consumer name for a unit.
  Future<void> updateDeviceName(String unitId, String name) async {
    await client.from(_unitsTable).update({'consumer_name': name}).eq('id', unitId);
  }

  /// Unadopts a device, releasing it back to factory state.
  ///
  /// Calls the `unadopt_device` Edge Function which:
  /// 1. Verifies the current user owns the device
  /// 2. Clears `consumer_user_id`, `consumer_name`, provisioning timestamps
  /// 3. Clears `provision_data` on the linked device
  /// 4. Revokes any device session tokens (Hubs must be re-adopted via BLE
  ///    before they can talk to authenticated cloud endpoints again)
  ///
  /// Provide either [macAddress] or [serialNumber] — the cloud accepts either.
  Future<void> unadoptDevice({String? macAddress, String? serialNumber}) async {
    assert(macAddress != null || serialNumber != null,
        'unadoptDevice requires macAddress or serialNumber');

    final body = <String, dynamic>{
      if (macAddress != null) 'mac_address': macAddress,
      if (serialNumber != null) 'serial_number': serialNumber,
    };

    final response = await client.functions.invoke('unadopt_device', body: body);

    if (response.status != 200) {
      final error = response.data?['error'] ?? 'Failed to unadopt device';
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

  /// Sends a command to a device by inserting into the device_commands table.
  ///
  /// The database broadcast trigger automatically routes the command to the
  /// device (directly or through its Hub for Thread mesh devices).
  Future<void> sendDeviceCommand({
    required String macAddress,
    required String command,
    Map<String, dynamic>? parameters,
  }) async {
    await client.from('device_commands').insert({
      'mac_address': macAddress,
      'command': command,
      'parameters': parameters ?? {},
    });
  }

}
