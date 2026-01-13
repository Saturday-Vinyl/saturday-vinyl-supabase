import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/album_location.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/providers/supabase_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Table name for album locations.
const _tableName = 'album_locations';

/// State for realtime album location updates.
class RealtimeAlbumLocationState {
  /// All current album locations (albums present in crates).
  final List<AlbumLocation> locations;

  /// Whether the initial fetch is loading.
  final bool isLoading;

  /// Error message if something went wrong.
  final String? error;

  /// When the state was last updated.
  final DateTime? lastUpdated;

  const RealtimeAlbumLocationState({
    this.locations = const [],
    this.isLoading = true,
    this.error,
    this.lastUpdated,
  });

  /// Get location for a specific album.
  AlbumLocation? getLocationForAlbum(String libraryAlbumId) {
    try {
      return locations.firstWhere(
        (loc) => loc.libraryAlbumId == libraryAlbumId && loc.isPresent,
      );
    } catch (_) {
      return null;
    }
  }

  /// Get all albums in a specific crate.
  List<AlbumLocation> getAlbumsInCrate(String deviceId) {
    return locations
        .where((loc) => loc.deviceId == deviceId && loc.isPresent)
        .toList();
  }

  /// Get locations grouped by crate (device ID).
  Map<String, List<AlbumLocation>> get locationsByCrate {
    final result = <String, List<AlbumLocation>>{};
    for (final location in locations.where((loc) => loc.isPresent)) {
      result.putIfAbsent(location.deviceId, () => []).add(location);
    }
    return result;
  }

  /// Get count of albums in each crate.
  Map<String, int> get albumCountsByCrate {
    return locationsByCrate.map(
      (deviceId, locs) => MapEntry(deviceId, locs.length),
    );
  }

  /// Get list of library album IDs that are currently in crates.
  Set<String> get locatedAlbumIds {
    return locations
        .where((loc) => loc.isPresent)
        .map((loc) => loc.libraryAlbumId)
        .toSet();
  }

  RealtimeAlbumLocationState copyWith({
    List<AlbumLocation>? locations,
    bool? isLoading,
    String? error,
    DateTime? lastUpdated,
    bool clearError = false,
  }) {
    return RealtimeAlbumLocationState(
      locations: locations ?? this.locations,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

/// StateNotifier for managing realtime album location state.
class RealtimeAlbumLocationNotifier
    extends StateNotifier<RealtimeAlbumLocationState> {
  RealtimeAlbumLocationNotifier(this._ref)
      : super(const RealtimeAlbumLocationState()) {
    _initialize();
  }

  final Ref _ref;
  RealtimeChannel? _channel;
  String? _currentLibraryId;

  /// Initialize the realtime subscription.
  Future<void> _initialize() async {
    // Watch for library changes and reinitialize when library changes
    _ref.listen<String?>(currentLibraryIdProvider, (previous, next) {
      if (next != null && next != _currentLibraryId) {
        _currentLibraryId = next;
        _reinitialize(next);
      }
    });

    final libraryId = _ref.read(currentLibraryIdProvider);
    if (libraryId != null) {
      _currentLibraryId = libraryId;
      await _fetchLocations(libraryId);
      _subscribeToLocations(libraryId);
    } else {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Reinitialize when library changes.
  Future<void> _reinitialize(String libraryId) async {
    // Unsubscribe from previous channel
    await _channel?.unsubscribe();
    _channel = null;

    // Reset state
    state = const RealtimeAlbumLocationState();

    // Fetch and subscribe for new library
    await _fetchLocations(libraryId);
    _subscribeToLocations(libraryId);
  }

  /// Fetch all current locations for the library.
  Future<void> _fetchLocations(String libraryId) async {
    try {
      final locationRepo = _ref.read(albumLocationRepositoryProvider);
      final locations =
          await locationRepo.getCurrentLocationsForLibrary(libraryId);

      state = state.copyWith(
        locations: locations,
        isLoading: false,
        lastUpdated: DateTime.now(),
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to fetch album locations: $e',
      );
    }
  }

  /// Subscribe to realtime location changes.
  ///
  /// Note: We subscribe to all location changes and filter client-side
  /// since the filter needs to go through library_albums table.
  void _subscribeToLocations(String libraryId) {
    final client = _ref.read(supabaseClientProvider);

    _channel = client
        .channel('album_locations_$libraryId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _tableName,
          callback: (payload) {
            _handleRealtimePayload(payload, libraryId);
          },
        )
        .subscribe();
  }

  /// Handle incoming realtime payloads.
  Future<void> _handleRealtimePayload(
    PostgresChangePayload payload,
    String libraryId,
  ) async {
    switch (payload.eventType) {
      case PostgresChangeEvent.insert:
        await _handleInsert(payload.newRecord, libraryId);
        break;
      case PostgresChangeEvent.update:
        await _handleUpdate(payload.newRecord, libraryId);
        break;
      case PostgresChangeEvent.delete:
        _handleDelete(payload.oldRecord);
        break;
      default:
        break;
    }
  }

  /// Handle a new location being inserted.
  Future<void> _handleInsert(
    Map<String, dynamic> record,
    String libraryId,
  ) async {
    final location = AlbumLocation.fromJson(record);

    // Check if this album belongs to our library
    if (!await _isInLibrary(location.libraryAlbumId, libraryId)) {
      return;
    }

    // Only add if this is a "present" location
    if (location.isPresent) {
      // Remove any existing location for this album first
      final locations = state.locations
          .where((loc) => loc.libraryAlbumId != location.libraryAlbumId)
          .toList();
      locations.add(location);

      state = state.copyWith(
        locations: locations,
        lastUpdated: DateTime.now(),
      );
    }
  }

  /// Handle an existing location being updated.
  Future<void> _handleUpdate(
    Map<String, dynamic> record,
    String libraryId,
  ) async {
    final updatedLocation = AlbumLocation.fromJson(record);

    // Check if this album belongs to our library
    if (!await _isInLibrary(updatedLocation.libraryAlbumId, libraryId)) {
      return;
    }

    if (updatedLocation.isPresent) {
      // Update existing or add new
      final index = state.locations.indexWhere((loc) => loc.id == updatedLocation.id);
      final locations = [...state.locations];

      if (index >= 0) {
        locations[index] = updatedLocation;
      } else {
        // Remove any other location for this album and add new one
        locations.removeWhere(
            (loc) => loc.libraryAlbumId == updatedLocation.libraryAlbumId);
        locations.add(updatedLocation);
      }

      state = state.copyWith(
        locations: locations,
        lastUpdated: DateTime.now(),
      );
    } else {
      // Album was removed from crate - remove from our list
      final locations =
          state.locations.where((loc) => loc.id != updatedLocation.id).toList();

      state = state.copyWith(
        locations: locations,
        lastUpdated: DateTime.now(),
      );
    }
  }

  /// Handle a location being deleted.
  void _handleDelete(Map<String, dynamic> record) {
    final deletedId = record['id'] as String?;
    if (deletedId == null) return;

    final locations =
        state.locations.where((loc) => loc.id != deletedId).toList();

    state = state.copyWith(
      locations: locations,
      lastUpdated: DateTime.now(),
    );
  }

  /// Check if a library album belongs to the current library.
  Future<bool> _isInLibrary(String libraryAlbumId, String libraryId) async {
    try {
      final client = _ref.read(supabaseClientProvider);
      final response = await client
          .from('library_albums')
          .select('library_id')
          .eq('id', libraryAlbumId)
          .eq('library_id', libraryId)
          .maybeSingle();

      return response != null;
    } catch (_) {
      return false;
    }
  }

  /// Force refresh all locations.
  Future<void> refresh() async {
    if (_currentLibraryId == null) return;

    state = state.copyWith(isLoading: true);
    await _fetchLocations(_currentLibraryId!);
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

/// Provider for realtime album location state.
final realtimeAlbumLocationProvider = StateNotifierProvider<
    RealtimeAlbumLocationNotifier, RealtimeAlbumLocationState>((ref) {
  return RealtimeAlbumLocationNotifier(ref);
});

/// Provider for location of a specific album.
final albumLocationProvider =
    Provider.family<AlbumLocation?, String>((ref, libraryAlbumId) {
  return ref
      .watch(realtimeAlbumLocationProvider)
      .getLocationForAlbum(libraryAlbumId);
});

/// Provider for albums in a specific crate.
final albumsInCrateProvider =
    Provider.family<List<AlbumLocation>, String>((ref, deviceId) {
  return ref.watch(realtimeAlbumLocationProvider).getAlbumsInCrate(deviceId);
});

/// Provider for locations grouped by crate.
final locationsByCrateProvider = Provider<Map<String, List<AlbumLocation>>>((ref) {
  return ref.watch(realtimeAlbumLocationProvider).locationsByCrate;
});

/// Provider for album counts by crate.
final albumCountsByCrateProvider = Provider<Map<String, int>>((ref) {
  return ref.watch(realtimeAlbumLocationProvider).albumCountsByCrate;
});

/// Provider for set of located album IDs.
final locatedAlbumIdsProvider = Provider<Set<String>>((ref) {
  return ref.watch(realtimeAlbumLocationProvider).locatedAlbumIds;
});
