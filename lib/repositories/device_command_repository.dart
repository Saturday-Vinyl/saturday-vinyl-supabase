import 'package:saturday_app/models/device_command.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:uuid/uuid.dart';

/// Repository for managing device commands
///
/// Commands are inserted into the device_commands table and broadcast
/// to devices via Supabase Realtime websockets.
class DeviceCommandRepository {
  final _supabase = SupabaseService.instance.client;
  final _uuid = const Uuid();

  // ============================================================================
  // Command Creation
  // ============================================================================

  /// Send a command to a device
  ///
  /// Inserts a command into device_commands table. The database trigger
  /// broadcasts it via Supabase Realtime to the device channel.
  Future<DeviceCommand> sendCommand({
    required String macAddress,
    required String command,
    String? capability,
    String? testName,
    Map<String, dynamic>? parameters,
    int priority = 0,
    Duration? expiresIn,
    String? createdBy,
  }) async {
    try {
      AppLogger.info('Sending command "$command" to device: $macAddress');

      final commandId = _uuid.v4();
      final now = DateTime.now();

      final commandData = {
        'id': commandId,
        'mac_address': macAddress,
        'command': command,
        if (capability != null) 'capability': capability,
        if (testName != null) 'test_name': testName,
        'parameters': parameters ?? {},
        'priority': priority,
        'status': 'pending',
        if (expiresIn != null)
          'expires_at': now.add(expiresIn).toIso8601String(),
        if (createdBy != null) 'created_by': createdBy,
      };

      final response = await _supabase
          .from('device_commands')
          .insert(commandData)
          .select()
          .single();

      final deviceCommand = DeviceCommand.fromJson(response);
      AppLogger.info(
          'Command sent successfully: ${deviceCommand.id} (${deviceCommand.command})');
      return deviceCommand;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to send command', error, stackTrace);
      rethrow;
    }
  }

  /// Send get_status command
  Future<DeviceCommand> sendGetStatus(String macAddress, {String? createdBy}) {
    return sendCommand(
      macAddress: macAddress,
      command: 'get_status',
      createdBy: createdBy,
    );
  }

  /// Send reboot command
  Future<DeviceCommand> sendReboot(String macAddress, {String? createdBy}) {
    return sendCommand(
      macAddress: macAddress,
      command: 'reboot',
      createdBy: createdBy,
    );
  }

  /// Send consumer_reset command
  Future<DeviceCommand> sendConsumerReset(String macAddress,
      {String? createdBy}) {
    return sendCommand(
      macAddress: macAddress,
      command: 'consumer_reset',
      createdBy: createdBy,
    );
  }

  /// Send factory_reset command
  Future<DeviceCommand> sendFactoryReset(String macAddress,
      {String? createdBy}) {
    return sendCommand(
      macAddress: macAddress,
      command: 'factory_reset',
      createdBy: createdBy,
    );
  }

  /// Send run_test command
  Future<DeviceCommand> sendRunTest({
    required String macAddress,
    required String capability,
    required String testName,
    Map<String, dynamic>? parameters,
    String? createdBy,
  }) {
    return sendCommand(
      macAddress: macAddress,
      command: 'run_test',
      capability: capability,
      testName: testName,
      parameters: parameters,
      createdBy: createdBy,
    );
  }

  // ============================================================================
  // Command Retrieval
  // ============================================================================

  /// Get a command by ID
  Future<DeviceCommand?> getCommand(String id) async {
    try {
      final response = await _supabase
          .from('device_commands')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return DeviceCommand.fromJson(response);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get command: $id', error, stackTrace);
      rethrow;
    }
  }

  /// Get recent commands for a device
  Future<List<DeviceCommand>> getRecentCommands(
    String macAddress, {
    int limit = 50,
    DateTime? since,
  }) async {
    try {
      var query = _supabase
          .from('device_commands')
          .select()
          .eq('mac_address', macAddress);

      if (since != null) {
        query = query.gte('created_at', since.toIso8601String());
      }

      final response =
          await query.order('created_at', ascending: false).limit(limit);

      return (response as List)
          .map((json) => DeviceCommand.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to get recent commands for: $macAddress', error, stackTrace);
      rethrow;
    }
  }

  /// Get recent commands for multiple devices
  Future<List<DeviceCommand>> getCommandsForDevices(
    List<String> macAddresses, {
    int limit = 100,
    DateTime? since,
  }) async {
    try {
      if (macAddresses.isEmpty) return [];

      var query = _supabase
          .from('device_commands')
          .select()
          .inFilter('mac_address', macAddresses);

      if (since != null) {
        query = query.gte('created_at', since.toIso8601String());
      }

      final response =
          await query.order('created_at', ascending: false).limit(limit);

      return (response as List)
          .map((json) => DeviceCommand.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get commands for devices', error, stackTrace);
      rethrow;
    }
  }

  /// Get pending commands for a device
  Future<List<DeviceCommand>> getPendingCommands(String macAddress) async {
    try {
      final response = await _supabase
          .from('device_commands')
          .select()
          .eq('mac_address', macAddress)
          .inFilter('status', ['pending', 'sent'])
          .order('priority', ascending: false)
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => DeviceCommand.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to get pending commands for: $macAddress', error, stackTrace);
      rethrow;
    }
  }
}
