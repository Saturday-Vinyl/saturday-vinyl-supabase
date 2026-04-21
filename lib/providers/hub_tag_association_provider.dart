import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/device.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/supabase_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// State for the hub-based tag association flow.
class HubTagAssociationState {
  /// Whether we are actively waiting for the hub to scan a tag.
  final bool isWaiting;

  /// The hub selected for scanning.
  final Device? selectedHub;

  /// The EPC detected by the hub (set when the pending record is fulfilled).
  final String? detectedEpc;

  /// The database ID of the pending_tag_associations record.
  final String? pendingId;

  /// Error message, if any.
  final String? error;

  const HubTagAssociationState({
    this.isWaiting = false,
    this.selectedHub,
    this.detectedEpc,
    this.pendingId,
    this.error,
  });

  HubTagAssociationState copyWith({
    bool? isWaiting,
    Device? selectedHub,
    bool clearSelectedHub = false,
    String? detectedEpc,
    bool clearDetectedEpc = false,
    String? pendingId,
    bool clearPendingId = false,
    String? error,
    bool clearError = false,
  }) {
    return HubTagAssociationState(
      isWaiting: isWaiting ?? this.isWaiting,
      selectedHub:
          clearSelectedHub ? null : (selectedHub ?? this.selectedHub),
      detectedEpc:
          clearDetectedEpc ? null : (detectedEpc ?? this.detectedEpc),
      pendingId: clearPendingId ? null : (pendingId ?? this.pendingId),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Manages the hub-based tag association flow.
///
/// Creates a pending_tag_associations record in the database and subscribes
/// to Realtime updates. When the hub scans a tag, the edge function fulfills
/// the record and this provider detects the change via Realtime.
class HubTagAssociationNotifier
    extends StateNotifier<HubTagAssociationState> {
  HubTagAssociationNotifier(this._ref)
      : super(const HubTagAssociationState());

  final Ref _ref;
  RealtimeChannel? _channel;

  /// Start waiting for the hub to scan a tag.
  ///
  /// Creates a pending_tag_associations record and subscribes to Realtime
  /// updates on that record. Call [cancel] to stop waiting.
  Future<void> startWaiting(Device hub, String libraryAlbumId) async {
    final client = _ref.read(supabaseClientProvider);
    final userId = _ref.read(currentUserIdProvider);

    if (userId == null) {
      state = state.copyWith(error: 'Not signed in');
      return;
    }

    state = state.copyWith(
      isWaiting: true,
      selectedHub: hub,
      clearError: true,
      clearDetectedEpc: true,
      clearPendingId: true,
    );

    try {
      // Cancel any existing pending request for this user/hub
      await client
          .from('pending_tag_associations')
          .update({
            'status': 'cancelled',
            'cancelled_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('user_id', userId)
          .eq('unit_id', hub.serialNumber)
          .eq('status', 'pending');

      // Create new pending record
      final response = await client
          .from('pending_tag_associations')
          .insert({
            'user_id': userId,
            'unit_id': hub.serialNumber,
            'library_album_id': libraryAlbumId,
          })
          .select('id')
          .single();

      final pendingId = response['id'] as String;
      state = state.copyWith(pendingId: pendingId);

      debugPrint(
          '[HubTagAssoc] Created pending association: $pendingId for hub ${hub.serialNumber}');

      // Subscribe to Realtime updates on this record
      _subscribeToUpdates(pendingId);

      // Poll once in case the record was already fulfilled between insert
      // and subscription (race condition guard)
      await _pollForFulfillment(pendingId);
    } catch (e) {
      debugPrint('[HubTagAssoc] Error starting: $e');
      state = state.copyWith(
        isWaiting: false,
        error: 'Failed to start hub scan: $e',
      );
    }
  }

  /// Subscribe to Realtime Postgres Changes on the pending record.
  void _subscribeToUpdates(String pendingId) {
    final client = _ref.read(supabaseClientProvider);

    _channel?.unsubscribe();
    _channel = client
        .channel('pending_tag_assoc_$pendingId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'pending_tag_associations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: pendingId,
          ),
          callback: (payload) {
            debugPrint(
                '[HubTagAssoc] Realtime update: ${payload.newRecord}');
            _handleUpdate(payload.newRecord);
          },
        )
        .subscribe((status, [error]) {
      debugPrint('[HubTagAssoc] Subscription status: $status, error: $error');
    });
  }

  /// Handle a Realtime update on the pending record.
  void _handleUpdate(Map<String, dynamic> record) {
    final status = record['status'] as String?;
    final detectedEpc = record['detected_epc'] as String?;

    if (status == 'fulfilled' && detectedEpc != null) {
      debugPrint('[HubTagAssoc] Tag detected: $detectedEpc');
      _cleanup();
      state = state.copyWith(
        isWaiting: false,
        detectedEpc: detectedEpc,
      );
    }
  }

  /// Poll the pending record once to check if it was already fulfilled.
  Future<void> _pollForFulfillment(String pendingId) async {
    final client = _ref.read(supabaseClientProvider);

    try {
      final response = await client
          .from('pending_tag_associations')
          .select('status, detected_epc')
          .eq('id', pendingId)
          .single();

      if (response['status'] == 'fulfilled' &&
          response['detected_epc'] != null) {
        _cleanup();
        state = state.copyWith(
          isWaiting: false,
          detectedEpc: response['detected_epc'] as String,
        );
      }
    } catch (e) {
      debugPrint('[HubTagAssoc] Poll error: $e');
    }
  }

  /// Cancel the pending association and stop waiting.
  Future<void> cancel() async {
    final pendingId = state.pendingId;
    _cleanup();

    if (pendingId != null) {
      try {
        final client = _ref.read(supabaseClientProvider);
        await client
            .from('pending_tag_associations')
            .update({
              'status': 'cancelled',
              'cancelled_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', pendingId)
            .eq('status', 'pending');
      } catch (e) {
        debugPrint('[HubTagAssoc] Error cancelling: $e');
      }
    }

    state = const HubTagAssociationState();
  }

  /// Reset state for a new attempt (e.g., after wrong tag detected).
  void reset() {
    _cleanup();
    state = const HubTagAssociationState();
  }

  void _cleanup() {
    _channel?.unsubscribe();
    _channel = null;
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}

/// Provider for the hub-based tag association flow.
final hubTagAssociationProvider = StateNotifierProvider.autoDispose<
    HubTagAssociationNotifier, HubTagAssociationState>((ref) {
  return HubTagAssociationNotifier(ref);
});
