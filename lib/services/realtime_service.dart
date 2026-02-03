import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Callback type for realtime updates
typedef RealtimeUpdateCallback = void Function(Map<String, dynamic> record);

/// Service for managing Supabase Realtime subscriptions
///
/// Provides methods to subscribe to database changes for live updates.
class RealtimeService {
  final SupabaseClient _client;

  RealtimeService({SupabaseClient? client})
      : _client = client ?? SupabaseService.instance.client;

  /// Subscribe to device table updates
  ///
  /// Receives updates when devices are inserted, updated, or deleted.
  /// Useful for tracking connectivity (last_seen_at) and telemetry changes.
  RealtimeChannel subscribeToDevices({
    required void Function(PostgresChangePayload payload) onInsert,
    required void Function(PostgresChangePayload payload) onUpdate,
    void Function(PostgresChangePayload payload)? onDelete,
  }) {
    AppLogger.info('Subscribing to devices realtime channel');

    final channel = _client.channel('devices-realtime');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'devices',
          callback: (payload) {
            AppLogger.info(
                'Realtime: Device INSERT - id=${payload.newRecord['id']}, mac=${payload.newRecord['mac_address']}');
            onInsert(payload);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'devices',
          callback: (payload) {
            final record = payload.newRecord;
            AppLogger.info(
                'Realtime: Device UPDATE - id=${record['id']}, mac=${record['mac_address']}, '
                'unit_id=${record['unit_id']}, last_seen=${record['last_seen_at']}');
            AppLogger.debug('Realtime: Device telemetry=${record['latest_telemetry']}');
            onUpdate(payload);
          },
        );

    if (onDelete != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'devices',
        callback: (payload) {
          AppLogger.info('Realtime: Device DELETE - id=${payload.oldRecord['id']}');
          onDelete(payload);
        },
      );
    }

    channel.subscribe((status, error) {
      if (error != null) {
        AppLogger.error('Devices realtime channel error', error, StackTrace.current);
      } else {
        AppLogger.info('Devices realtime channel status: $status');
        if (status.toString() == 'RealtimeSubscribeStatus.subscribed') {
          AppLogger.info('Devices realtime subscription ACTIVE - listening for changes');
        }
      }
    });

    return channel;
  }

  /// Subscribe to unit table updates
  ///
  /// Receives updates when units are inserted, updated, or deleted.
  /// Useful for tracking status changes and new unit creation.
  RealtimeChannel subscribeToUnits({
    required void Function(PostgresChangePayload payload) onInsert,
    required void Function(PostgresChangePayload payload) onUpdate,
    void Function(PostgresChangePayload payload)? onDelete,
  }) {
    AppLogger.info('Subscribing to units realtime channel');

    final channel = _client.channel('units-realtime');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'units',
          callback: (payload) {
            AppLogger.info(
                'Realtime: Unit INSERT - id=${payload.newRecord['id']}, serial=${payload.newRecord['serial_number']}');
            onInsert(payload);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'units',
          callback: (payload) {
            final record = payload.newRecord;
            AppLogger.info(
                'Realtime: Unit UPDATE - id=${record['id']}, serial=${record['serial_number']}, status=${record['status']}');
            onUpdate(payload);
          },
        );

    if (onDelete != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'units',
        callback: (payload) {
          AppLogger.info('Realtime: Unit DELETE - id=${payload.oldRecord['id']}');
          onDelete(payload);
        },
      );
    }

    channel.subscribe((status, error) {
      if (error != null) {
        AppLogger.error('Units realtime channel error', error, StackTrace.current);
      } else {
        AppLogger.info('Units realtime channel status: $status');
        if (status.toString() == 'RealtimeSubscribeStatus.subscribed') {
          AppLogger.info('Units realtime subscription ACTIVE - listening for changes');
        }
      }
    });

    return channel;
  }

  /// Subscribe to device_heartbeats for specific MAC addresses
  ///
  /// Receives heartbeat inserts for the specified devices.
  /// Used for remote device monitoring.
  RealtimeChannel subscribeToHeartbeatsByMacs({
    required List<String> macAddresses,
    required void Function(PostgresChangePayload payload) onInsert,
  }) {
    if (macAddresses.isEmpty) {
      throw ArgumentError('macAddresses cannot be empty');
    }

    final channelName = 'heartbeats-${macAddresses.hashCode}';
    AppLogger.info(
        'Subscribing to heartbeats for ${macAddresses.length} devices: $channelName');

    final channel = _client.channel(channelName);

    // Subscribe to heartbeats with MAC filter
    // Note: Supabase Realtime filter uses 'in' for array matching
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'device_heartbeats',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.inFilter,
        column: 'mac_address',
        value: macAddresses,
      ),
      callback: (payload) {
        final record = payload.newRecord;
        AppLogger.debug(
            'Realtime: Heartbeat INSERT - mac=${record['mac_address']}, type=${record['type']}');
        onInsert(payload);
      },
    );

    channel.subscribe((status, error) {
      if (error != null) {
        AppLogger.error(
            'Heartbeats realtime channel error', error, StackTrace.current);
      } else {
        AppLogger.info('Heartbeats realtime channel status: $status');
        if (status.toString() == 'RealtimeSubscribeStatus.subscribed') {
          AppLogger.info(
              'Heartbeats realtime subscription ACTIVE for ${macAddresses.length} devices');
        }
      }
    });

    return channel;
  }

  /// Subscribe to device_commands for specific MAC addresses
  ///
  /// Receives command inserts and updates for the specified devices.
  /// Used for remote device monitoring.
  RealtimeChannel subscribeToCommandsByMacs({
    required List<String> macAddresses,
    required void Function(PostgresChangePayload payload) onInsert,
    required void Function(PostgresChangePayload payload) onUpdate,
  }) {
    if (macAddresses.isEmpty) {
      throw ArgumentError('macAddresses cannot be empty');
    }

    final channelName = 'commands-${macAddresses.hashCode}';
    AppLogger.info(
        'Subscribing to commands for ${macAddresses.length} devices: $channelName');

    final channel = _client.channel(channelName);

    // Subscribe to command inserts
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'device_commands',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.inFilter,
        column: 'mac_address',
        value: macAddresses,
      ),
      callback: (payload) {
        final record = payload.newRecord;
        AppLogger.debug(
            'Realtime: Command INSERT - id=${record['id']}, cmd=${record['command']}');
        onInsert(payload);
      },
    );

    // Subscribe to command updates (status changes)
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'device_commands',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.inFilter,
        column: 'mac_address',
        value: macAddresses,
      ),
      callback: (payload) {
        final record = payload.newRecord;
        AppLogger.debug(
            'Realtime: Command UPDATE - id=${record['id']}, status=${record['status']}');
        onUpdate(payload);
      },
    );

    channel.subscribe((status, error) {
      if (error != null) {
        AppLogger.error(
            'Commands realtime channel error', error, StackTrace.current);
      } else {
        AppLogger.info('Commands realtime channel status: $status');
        if (status.toString() == 'RealtimeSubscribeStatus.subscribed') {
          AppLogger.info(
              'Commands realtime subscription ACTIVE for ${macAddresses.length} devices');
        }
      }
    });

    return channel;
  }

  /// Unsubscribe from a channel and remove it
  Future<void> unsubscribe(RealtimeChannel channel) async {
    try {
      await _client.removeChannel(channel);
      AppLogger.info('Unsubscribed from realtime channel');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to unsubscribe from channel', error, stackTrace);
    }
  }

  /// Unsubscribe from all channels
  Future<void> unsubscribeAll() async {
    try {
      await _client.removeAllChannels();
      AppLogger.info('Unsubscribed from all realtime channels');
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to unsubscribe from all channels', error, stackTrace);
    }
  }
}
