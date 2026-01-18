import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/device.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/models/now_playing_detection.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/now_playing_provider.dart';
import 'package:saturday_consumer_app/providers/realtime_device_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/providers/supabase_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// State for realtime Now Playing detection from hubs.
class RealtimeNowPlayingState {
  /// The current "placed" event from the hub, if any.
  final NowPlayingEvent? currentEvent;

  /// The resolved library album for the detected EPC.
  final LibraryAlbum? resolvedAlbum;

  /// The device that detected the record.
  final Device? device;

  /// Whether we're currently loading/resolving the album.
  final bool isResolving;

  /// Error message if resolution failed.
  final String? error;

  /// Pre-resolved album info from the notification (used with new architecture).
  final UserNowPlayingNotification? notification;

  const RealtimeNowPlayingState({
    this.currentEvent,
    this.resolvedAlbum,
    this.device,
    this.isResolving = false,
    this.error,
    this.notification,
  });

  /// Whether there is an active detection (a "placed" event without a subsequent "removed").
  bool get hasActiveDetection {
    // New architecture: check notification
    if (notification != null) {
      return notification!.eventType == 'placed';
    }
    // Legacy: check currentEvent
    return currentEvent != null && currentEvent!.isPlaced;
  }

  /// Whether the detection was successfully resolved to an album.
  bool get isResolved => resolvedAlbum != null || notification?.libraryAlbumId != null;

  /// The name of the device that detected the record.
  String? get deviceName => notification?.deviceName ?? device?.name;

  /// Album title from pre-resolved notification data.
  String? get albumTitle => notification?.albumTitle;

  /// Album artist from pre-resolved notification data.
  String? get albumArtist => notification?.albumArtist;

  /// Cover image URL from pre-resolved notification data.
  String? get coverImageUrl => notification?.coverImageUrl;

  RealtimeNowPlayingState copyWith({
    NowPlayingEvent? currentEvent,
    LibraryAlbum? resolvedAlbum,
    Device? device,
    bool? isResolving,
    String? error,
    UserNowPlayingNotification? notification,
    bool clearCurrentEvent = false,
    bool clearResolvedAlbum = false,
    bool clearDevice = false,
    bool clearError = false,
    bool clearNotification = false,
  }) {
    return RealtimeNowPlayingState(
      currentEvent:
          clearCurrentEvent ? null : (currentEvent ?? this.currentEvent),
      resolvedAlbum:
          clearResolvedAlbum ? null : (resolvedAlbum ?? this.resolvedAlbum),
      device: clearDevice ? null : (device ?? this.device),
      isResolving: isResolving ?? this.isResolving,
      error: clearError ? null : (error ?? this.error),
      notification: clearNotification ? null : (notification ?? this.notification),
    );
  }
}

/// User-facing notification with pre-resolved album data.
///
/// This is populated by the Edge Function from the hub events and includes
/// all the resolved album information so the app doesn't need to make
/// additional queries.
class UserNowPlayingNotification {
  final String id;
  final String userId;
  final String sourceEventId;
  final String unitId;
  final String epc;
  final String eventType;
  final String? libraryAlbumId;
  final String? albumTitle;
  final String? albumArtist;
  final String? coverImageUrl;
  final String? libraryId;
  final String? libraryName;
  final String? deviceId;
  final String? deviceName;
  final DateTime eventTimestamp;
  final DateTime createdAt;

  const UserNowPlayingNotification({
    required this.id,
    required this.userId,
    required this.sourceEventId,
    required this.unitId,
    required this.epc,
    required this.eventType,
    this.libraryAlbumId,
    this.albumTitle,
    this.albumArtist,
    this.coverImageUrl,
    this.libraryId,
    this.libraryName,
    this.deviceId,
    this.deviceName,
    required this.eventTimestamp,
    required this.createdAt,
  });

  factory UserNowPlayingNotification.fromJson(Map<String, dynamic> json) {
    return UserNowPlayingNotification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      sourceEventId: json['source_event_id'] as String,
      unitId: json['unit_id'] as String,
      epc: json['epc'] as String,
      eventType: json['event_type'] as String,
      libraryAlbumId: json['library_album_id'] as String?,
      albumTitle: json['album_title'] as String?,
      albumArtist: json['album_artist'] as String?,
      coverImageUrl: json['cover_image_url'] as String?,
      libraryId: json['library_id'] as String?,
      libraryName: json['library_name'] as String?,
      deviceId: json['device_id'] as String?,
      deviceName: json['device_name'] as String?,
      eventTimestamp: DateTime.parse(json['event_timestamp'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isPlaced => eventType == 'placed';
  bool get isRemoved => eventType == 'removed';
  bool get hasAlbumInfo => libraryAlbumId != null;
}

/// Table name for user-facing notifications (new scalable architecture).
const _userNotificationsTable = 'user_now_playing_notifications';

/// Table name for raw now playing events (legacy/fallback).
const _legacyEventsTable = 'now_playing_events';

/// StateNotifier for managing realtime Now Playing event state.
///
/// This subscribes to `user_now_playing_notifications` which is RLS-protected
/// so only the current user's notifications are received. The Edge Function
/// pre-resolves the EPC to album info, so no additional queries are needed.
class RealtimeNowPlayingNotifier
    extends StateNotifier<RealtimeNowPlayingState> {
  RealtimeNowPlayingNotifier(this._ref)
      : super(const RealtimeNowPlayingState()) {
    // Listen for auth state changes to reinitialize when user logs in
    _ref.listen<String?>(currentUserIdProvider, (previous, next) {
      debugPrint(
          '[RealtimeNowPlaying] Auth state changed: $previous -> $next');
      if (next != null && previous != next) {
        _initialize();
      } else if (next == null && previous != null) {
        // User logged out - clean up
        _cleanup();
      }
    });

    // Also try to initialize immediately in case user is already logged in
    _initialize();
  }

  final Ref _ref;
  RealtimeChannel? _channel;
  RealtimeChannel? _legacyChannel;
  bool _isInitialized = false;
  Timer? _presenceTimer;

  /// Whether to use the new scalable architecture (user_now_playing_notifications).
  /// Falls back to legacy (now_playing_events) if the new table doesn't exist.
  bool _useNewArchitecture = true;

  /// Cache of user's hub serial numbers for filtering legacy events.
  Set<String> _userHubSerialNumbers = {};

  /// Initialize the realtime subscription.
  Future<void> _initialize() async {
    final userId = _ref.read(currentUserIdProvider);
    debugPrint('[RealtimeNowPlaying] Initializing for user: $userId');
    if (userId == null) {
      debugPrint('[RealtimeNowPlaying] No user ID, skipping initialization');
      return;
    }

    // Clean up any existing subscription before reinitializing
    if (_isInitialized) {
      debugPrint('[RealtimeNowPlaying] Already initialized, cleaning up first');
      await _cleanup();
    }

    // Try to subscribe to the new user_now_playing_notifications table first
    // This table is RLS-protected so we only receive our own notifications
    try {
      await _subscribeToUserNotifications();
      _useNewArchitecture = true;
      debugPrint('[RealtimeNowPlaying] Using new scalable architecture');
    } catch (e) {
      debugPrint('[RealtimeNowPlaying] New architecture failed, falling back to legacy: $e');
      _useNewArchitecture = false;

      // Fall back to legacy: load hub serial numbers and subscribe to all events
      await _loadUserHubSerialNumbers();
      if (_userHubSerialNumbers.isNotEmpty) {
        await _fetchCurrentEventLegacy();
        _subscribeToLegacyEvents();
      }
    }

    // Start presence updates to indicate app is connected
    _startPresenceUpdates();

    _isInitialized = true;
  }

  /// Clean up subscriptions and timers.
  Future<void> _cleanup() async {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    await _channel?.unsubscribe();
    _channel = null;
    await _legacyChannel?.unsubscribe();
    _legacyChannel = null;
    _isInitialized = false;

    state = const RealtimeNowPlayingState();
  }

  /// Subscribe to user_now_playing_notifications (new architecture).
  Future<void> _subscribeToUserNotifications() async {
    final client = _ref.read(supabaseClientProvider);
    final userId = _ref.read(currentUserIdProvider);

    if (userId == null) return;

    debugPrint('[RealtimeNowPlaying] Subscribing to $_userNotificationsTable...');

    // Fetch the most recent notification to set initial state
    await _fetchCurrentNotification();

    // Subscribe to realtime changes - RLS ensures we only get our notifications
    _channel = client
        .channel('user_now_playing_notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: _userNotificationsTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            debugPrint(
                '[RealtimeNowPlaying] Received notification: ${payload.newRecord}');
            _handleNotificationInsert(payload.newRecord);
          },
        )
        .subscribe((status, [error]) {
      debugPrint(
          '[RealtimeNowPlaying] Subscription status: $status, error: $error');
      if (status == RealtimeSubscribeStatus.subscribed) {
        debugPrint('[RealtimeNowPlaying] Successfully subscribed to user notifications');
      }
    });
  }

  /// Fetch the most recent notification on startup.
  Future<void> _fetchCurrentNotification() async {
    final client = _ref.read(supabaseClientProvider);
    final userId = _ref.read(currentUserIdProvider);

    if (userId == null) return;

    try {
      // Get the most recent "placed" notification
      final response = await client
          .from(_userNotificationsTable)
          .select()
          .eq('user_id', userId)
          .eq('event_type', 'placed')
          .order('event_timestamp', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        final notification = UserNowPlayingNotification.fromJson(response);

        // Check if there's a "removed" notification after this
        final removedCheck = await client
            .from(_userNotificationsTable)
            .select('id')
            .eq('user_id', userId)
            .eq('unit_id', notification.unitId)
            .eq('epc', notification.epc)
            .eq('event_type', 'removed')
            .gt('event_timestamp', notification.eventTimestamp.toIso8601String())
            .limit(1)
            .maybeSingle();

        if (removedCheck == null) {
          // No removal - record is still playing
          debugPrint('[RealtimeNowPlaying] Found active notification: ${notification.albumTitle}');
          state = state.copyWith(notification: notification);

          // If we have album info, push to Now Playing provider
          if (notification.hasAlbumInfo) {
            await _updateNowPlayingFromNotification(notification);
          }
        }
      }
    } catch (e) {
      debugPrint('[RealtimeNowPlaying] Error fetching current notification: $e');
      rethrow; // Let caller handle fallback to legacy
    }
  }

  /// Handle a new notification being inserted.
  Future<void> _handleNotificationInsert(Map<String, dynamic> record) async {
    final notification = UserNowPlayingNotification.fromJson(record);

    if (notification.isPlaced) {
      // New record placed on hub
      state = state.copyWith(
        notification: notification,
        clearCurrentEvent: true,
        clearResolvedAlbum: true,
        clearError: true,
      );

      if (notification.hasAlbumInfo) {
        await _updateNowPlayingFromNotification(notification);
      } else {
        state = state.copyWith(
          error: 'Unknown record - tag not associated with any album',
        );
      }
    } else if (notification.isRemoved) {
      // Record removed - clear state if it matches current
      if (state.notification != null &&
          state.notification!.epc == notification.epc &&
          state.notification!.unitId == notification.unitId) {
        state = state.copyWith(
          clearNotification: true,
          clearCurrentEvent: true,
          clearResolvedAlbum: true,
          clearDevice: true,
          clearError: true,
        );

        _clearNowPlaying();
      }
    }
  }

  /// Update the main Now Playing provider from a notification.
  Future<void> _updateNowPlayingFromNotification(
      UserNowPlayingNotification notification) async {
    // Try to fetch the full LibraryAlbum if we have the ID
    if (notification.libraryAlbumId != null) {
      try {
        final albumRepo = _ref.read(albumRepositoryProvider);
        final libraryAlbum = await albumRepo.getLibraryAlbum(
            notification.libraryAlbumId!);

        if (libraryAlbum != null) {
          state = state.copyWith(resolvedAlbum: libraryAlbum);

          final nowPlayingNotifier = _ref.read(nowPlayingProvider.notifier);
          nowPlayingNotifier.setAutoDetected(
            libraryAlbum,
            deviceName: notification.deviceName ?? 'Saturday Hub',
            detectedAt: notification.eventTimestamp,
          );
          return;
        }
      } catch (e) {
        debugPrint('[RealtimeNowPlaying] Error fetching library album: $e');
      }
    }

    // Fallback: we have album info from notification but couldn't fetch full object
    // The UI can still display using notification.albumTitle, albumArtist, etc.
    debugPrint('[RealtimeNowPlaying] Using pre-resolved album info from notification');
  }

  /// Start periodic presence updates.
  void _startPresenceUpdates() {
    // Update presence every 2 minutes while connected
    _presenceTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _updatePresence();
    });

    // Also update immediately
    _updatePresence();
  }

  /// Update presence to indicate app is connected.
  Future<void> _updatePresence() async {
    // This is handled by the PushTokenService in the full implementation
    // For now, we just log that we would update presence
    debugPrint('[RealtimeNowPlaying] Would update presence timestamp');
  }

  // ============================================================================
  // LEGACY SUPPORT (now_playing_events table)
  // ============================================================================

  /// Load the user's hub serial numbers from the device provider.
  Future<void> _loadUserHubSerialNumbers() async {
    try {
      final deviceState = _ref.read(realtimeDeviceProvider);
      debugPrint(
          '[RealtimeNowPlaying] Device state isLoading: ${deviceState.isLoading}, devices: ${deviceState.devices.length}');
      final hubs = deviceState.hubs;
      debugPrint('[RealtimeNowPlaying] Hubs from provider: ${hubs.length}');

      // If device provider is still loading or has no hubs, fetch directly
      if (hubs.isEmpty) {
        debugPrint(
            '[RealtimeNowPlaying] No hubs in provider, fetching directly');
        final userId = _ref.read(currentUserIdProvider);
        if (userId == null) return;

        final deviceRepo = _ref.read(deviceRepositoryProvider);
        final fetchedHubs = await deviceRepo.getUserHubs(userId);
        _userHubSerialNumbers =
            fetchedHubs.map((h) => h.serialNumber).toSet();
        debugPrint(
            '[RealtimeNowPlaying] Fetched hubs directly: $_userHubSerialNumbers');
      } else {
        _userHubSerialNumbers = hubs.map((h) => h.serialNumber).toSet();
      }
    } catch (e) {
      debugPrint('[RealtimeNowPlaying] Error loading hubs: $e');
      // If device provider isn't ready, try fetching directly
      final userId = _ref.read(currentUserIdProvider);
      if (userId == null) return;

      final deviceRepo = _ref.read(deviceRepositoryProvider);
      final hubs = await deviceRepo.getUserHubs(userId);
      _userHubSerialNumbers = hubs.map((h) => h.serialNumber).toSet();
      debugPrint(
          '[RealtimeNowPlaying] Fetched hubs after error: $_userHubSerialNumbers');
    }
  }

  /// Find the Device object for a given unit_id (serial number).
  Device? _getDeviceBySerialNumber(String serialNumber) {
    final deviceState = _ref.read(realtimeDeviceProvider);
    try {
      return deviceState.devices.firstWhere(
        (d) => d.serialNumber == serialNumber,
      );
    } catch (_) {
      return null;
    }
  }

  /// Fetch the most recent "placed" event for user's hubs on startup (legacy).
  Future<void> _fetchCurrentEventLegacy() async {
    if (_userHubSerialNumbers.isEmpty) return;

    try {
      final client = _ref.read(supabaseClientProvider);

      // Query for the most recent "placed" event from user's hubs
      final response = await client
          .from(_legacyEventsTable)
          .select()
          .inFilter('unit_id', _userHubSerialNumbers.toList())
          .eq('event_type', 'placed')
          .order('timestamp', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        final placedEvent = NowPlayingEvent.fromJson(response);

        // Check if there's a "removed" event after this "placed" event
        final removedCheck = await client
            .from(_legacyEventsTable)
            .select('id')
            .eq('unit_id', placedEvent.unitId)
            .eq('epc', placedEvent.epc)
            .eq('event_type', 'removed')
            .gt('timestamp', placedEvent.timestamp.toIso8601String())
            .limit(1)
            .maybeSingle();

        if (removedCheck == null) {
          // No removal event - this record is still playing
          final device = _getDeviceBySerialNumber(placedEvent.unitId);

          state = state.copyWith(
            currentEvent: placedEvent,
            device: device,
            isResolving: true,
          );

          // Resolve the EPC to a library album
          await _resolveEpc(placedEvent.epc);
        }
      }
    } catch (e) {
      state = state.copyWith(
        error: 'Failed to fetch current event: $e',
      );
    }
  }

  /// Subscribe to legacy realtime event changes.
  void _subscribeToLegacyEvents() {
    final client = _ref.read(supabaseClientProvider);
    debugPrint('[RealtimeNowPlaying] Subscribing to $_legacyEventsTable (legacy)...');

    _legacyChannel = client
        .channel('now_playing_events_legacy')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: _legacyEventsTable,
          callback: (payload) {
            debugPrint(
                '[RealtimeNowPlaying] Received legacy payload: ${payload.newRecord}');
            _handleLegacyRealtimePayload(payload);
          },
        )
        .subscribe((status, [error]) {
      debugPrint(
          '[RealtimeNowPlaying] Legacy subscription status: $status, error: $error');
    });
  }

  /// Handle incoming legacy realtime payloads.
  void _handleLegacyRealtimePayload(PostgresChangePayload payload) {
    if (payload.eventType != PostgresChangeEvent.insert) {
      return;
    }

    final record = payload.newRecord;
    final unitId = record['unit_id'] as String?;

    // Filter: only process events from user's hubs
    if (unitId == null || !_userHubSerialNumbers.contains(unitId)) {
      debugPrint(
          '[RealtimeNowPlaying] Filtering out legacy event - unit_id not in user hubs');
      return;
    }

    debugPrint('[RealtimeNowPlaying] Processing legacy event from user hub');
    _handleLegacyInsert(record);
  }

  /// Handle a legacy event being inserted.
  Future<void> _handleLegacyInsert(Map<String, dynamic> record) async {
    final event = NowPlayingEvent.fromJson(record);

    if (event.isPlaced) {
      // New record placed on hub
      final device = _getDeviceBySerialNumber(event.unitId);

      state = state.copyWith(
        currentEvent: event,
        device: device,
        isResolving: true,
        clearResolvedAlbum: true,
        clearError: true,
      );

      // Resolve the EPC to a library album
      await _resolveEpc(event.epc);
    } else if (event.isRemoved) {
      // Record removed from hub
      if (state.currentEvent != null &&
          state.currentEvent!.epc == event.epc &&
          state.currentEvent!.unitId == event.unitId) {
        state = state.copyWith(
          clearCurrentEvent: true,
          clearResolvedAlbum: true,
          clearDevice: true,
          clearError: true,
        );

        _clearNowPlaying();
      }
    }
  }

  /// Resolve an EPC to a library album (legacy).
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
    final detectedAt = state.currentEvent?.timestamp;

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

  /// Force refresh the current event state.
  Future<void> refresh() async {
    if (_useNewArchitecture) {
      state = state.copyWith(
        clearNotification: true,
        clearResolvedAlbum: true,
        clearError: true,
      );
      await _fetchCurrentNotification();
    } else {
      // Legacy refresh
      await _loadUserHubSerialNumbers();

      state = state.copyWith(
        clearCurrentEvent: true,
        clearResolvedAlbum: true,
        clearDevice: true,
        clearError: true,
      );

      await _fetchCurrentEventLegacy();
    }
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    _channel?.unsubscribe();
    _legacyChannel?.unsubscribe();
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
