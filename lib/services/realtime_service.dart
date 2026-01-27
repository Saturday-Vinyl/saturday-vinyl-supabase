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
