import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/models/now_playing_detection.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/now_playing_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/providers/supabase_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// State for realtime Now Playing detection from hubs.
class RealtimeNowPlayingState {
  /// The current detection from the hub, if any.
  final NowPlayingDetection? detection;

  /// The resolved library album for the detected EPC.
  final LibraryAlbum? resolvedAlbum;

  /// The name of the device that detected the record.
  final String? deviceName;

  /// Whether we're currently loading/resolving the album.
  final bool isResolving;

  /// Error message if resolution failed.
  final String? error;

  const RealtimeNowPlayingState({
    this.detection,
    this.resolvedAlbum,
    this.deviceName,
    this.isResolving = false,
    this.error,
  });

  /// Whether there is an active detection.
  bool get hasActiveDetection => detection != null && detection!.isActive;

  /// Whether the detection was successfully resolved to an album.
  bool get isResolved => resolvedAlbum != null;

  RealtimeNowPlayingState copyWith({
    NowPlayingDetection? detection,
    LibraryAlbum? resolvedAlbum,
    String? deviceName,
    bool? isResolving,
    String? error,
    bool clearDetection = false,
    bool clearResolvedAlbum = false,
    bool clearError = false,
  }) {
    return RealtimeNowPlayingState(
      detection: clearDetection ? null : (detection ?? this.detection),
      resolvedAlbum:
          clearResolvedAlbum ? null : (resolvedAlbum ?? this.resolvedAlbum),
      deviceName: deviceName ?? this.deviceName,
      isResolving: isResolving ?? this.isResolving,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Table name for now playing detections.
const _tableName = 'now_playing_detections';

/// StateNotifier for managing realtime Now Playing detection state.
class RealtimeNowPlayingNotifier extends StateNotifier<RealtimeNowPlayingState> {
  RealtimeNowPlayingNotifier(this._ref) : super(const RealtimeNowPlayingState()) {
    _initialize();
  }

  final Ref _ref;
  RealtimeChannel? _channel;

  /// Initialize the realtime subscription.
  Future<void> _initialize() async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;

    // First fetch the current active detection (if any)
    await _fetchCurrentDetection(userId);

    // Then subscribe to realtime changes
    _subscribeToDetections(userId);
  }

  /// Fetch the current active detection on startup.
  Future<void> _fetchCurrentDetection(String userId) async {
    try {
      final client = _ref.read(supabaseClientProvider);

      final response = await client
          .from(_tableName)
          .select('*, device:devices(name)')
          .eq('user_id', userId)
          .isFilter('removed_at', null)
          .order('detected_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        final detection = NowPlayingDetection.fromJson(response);
        final deviceName = response['device']?['name'] as String?;

        state = state.copyWith(
          detection: detection,
          deviceName: deviceName,
          isResolving: true,
        );

        // Resolve the EPC to a library album
        await _resolveEpc(detection.epcIdentifier);
      }
    } catch (e) {
      state = state.copyWith(
        error: 'Failed to fetch current detection: $e',
      );
    }
  }

  /// Subscribe to realtime detection changes.
  void _subscribeToDetections(String userId) {
    final client = _ref.read(supabaseClientProvider);

    _channel = client
        .channel('now_playing_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _tableName,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            _handleRealtimePayload(payload);
          },
        )
        .subscribe();
  }

  /// Handle incoming realtime payloads.
  void _handleRealtimePayload(PostgresChangePayload payload) {
    switch (payload.eventType) {
      case PostgresChangeEvent.insert:
        _handleInsert(payload.newRecord);
        break;
      case PostgresChangeEvent.update:
        _handleUpdate(payload.newRecord);
        break;
      case PostgresChangeEvent.delete:
        _handleDelete(payload.oldRecord);
        break;
      default:
        break;
    }
  }

  /// Handle a new detection being inserted.
  Future<void> _handleInsert(Map<String, dynamic> record) async {
    final detection = NowPlayingDetection.fromJson(record);

    // Only process if this is an active detection (no removed_at)
    if (!detection.isActive) return;

    state = state.copyWith(
      detection: detection,
      isResolving: true,
      clearResolvedAlbum: true,
      clearError: true,
    );

    // Fetch device name
    await _fetchDeviceName(detection.deviceId);

    // Resolve the EPC
    await _resolveEpc(detection.epcIdentifier);
  }

  /// Handle an existing detection being updated.
  Future<void> _handleUpdate(Map<String, dynamic> record) async {
    final detection = NowPlayingDetection.fromJson(record);

    // Check if this is for our current detection
    if (state.detection?.id != detection.id) {
      // This is a different detection becoming active
      if (detection.isActive) {
        await _handleInsert(record);
      }
      return;
    }

    // If the record was removed (removed_at is now set), clear state
    if (!detection.isActive) {
      state = state.copyWith(
        clearDetection: true,
        clearResolvedAlbum: true,
        clearError: true,
      );
      // Clear the main Now Playing provider
      _clearNowPlaying();
      return;
    }

    // If the library_album_id was updated (resolved server-side)
    if (detection.libraryAlbumId != null &&
        state.resolvedAlbum?.id != detection.libraryAlbumId) {
      state = state.copyWith(
        detection: detection,
        isResolving: true,
      );
      await _resolveEpc(detection.epcIdentifier);
    } else {
      state = state.copyWith(detection: detection);
    }
  }

  /// Handle a detection being deleted.
  void _handleDelete(Map<String, dynamic> record) {
    final deletedId = record['id'] as String?;

    // If this was our current detection, clear state
    if (state.detection?.id == deletedId) {
      state = state.copyWith(
        clearDetection: true,
        clearResolvedAlbum: true,
        clearError: true,
      );
      // Clear the main Now Playing provider
      _clearNowPlaying();
    }
  }

  /// Fetch the device name for display.
  Future<void> _fetchDeviceName(String deviceId) async {
    try {
      final deviceRepo = _ref.read(deviceRepositoryProvider);
      final device = await deviceRepo.getDevice(deviceId);
      if (device != null) {
        state = state.copyWith(deviceName: device.name);
      }
    } catch (_) {
      // Ignore errors fetching device name
    }
  }

  /// Resolve an EPC to a library album.
  Future<void> _resolveEpc(String epc) async {
    try {
      final tagRepo = _ref.read(tagRepositoryProvider);
      final libraryAlbum = await tagRepo.getLibraryAlbumByEpc(epc);

      if (libraryAlbum != null) {
        state = state.copyWith(
          resolvedAlbum: libraryAlbum,
          isResolving: false,
          clearError: true,
        );

        // Push the resolved album to the main Now Playing provider
        _updateNowPlaying(libraryAlbum);
      } else {
        state = state.copyWith(
          isResolving: false,
          error: 'Unknown record - tag not associated with any album',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isResolving: false,
        error: 'Failed to resolve album: $e',
      );
    }
  }

  /// Push the resolved album to the main Now Playing notifier.
  void _updateNowPlaying(LibraryAlbum album) {
    final nowPlayingNotifier = _ref.read(nowPlayingProvider.notifier);
    final deviceName = state.deviceName ?? 'Saturday Hub';
    final detectedAt = state.detection?.detectedAt;

    nowPlayingNotifier.setAutoDetected(
      album,
      deviceName: deviceName,
      detectedAt: detectedAt,
    );
  }

  /// Clear the Now Playing when detection is removed.
  void _clearNowPlaying() {
    final nowPlayingNotifier = _ref.read(nowPlayingProvider.notifier);
    nowPlayingNotifier.clearAutoDetected();
  }

  /// Force refresh the current detection state.
  Future<void> refresh() async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;

    state = state.copyWith(
      clearDetection: true,
      clearResolvedAlbum: true,
      clearError: true,
    );

    await _fetchCurrentDetection(userId);
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

/// Provider for realtime Now Playing state.
final realtimeNowPlayingProvider =
    StateNotifierProvider<RealtimeNowPlayingNotifier, RealtimeNowPlayingState>(
        (ref) {
  return RealtimeNowPlayingNotifier(ref);
});

/// Provider for whether there's an active auto-detected now playing.
final hasRealtimeDetectionProvider = Provider<bool>((ref) {
  return ref.watch(realtimeNowPlayingProvider).hasActiveDetection;
});

/// Provider for the auto-detected album (resolved from hub detection).
final realtimeDetectedAlbumProvider = Provider<LibraryAlbum?>((ref) {
  return ref.watch(realtimeNowPlayingProvider).resolvedAlbum;
});
