import 'package:saturday_consumer_app/models/album_location.dart';
import 'package:saturday_consumer_app/repositories/base_repository.dart';

/// Repository for album location-related database operations.
class AlbumLocationRepository extends BaseRepository {
  static const _tableName = 'album_locations';

  /// Gets the current location of an album (if present in a crate).
  ///
  /// Returns null if the album is not currently in any crate.
  Future<AlbumLocation?> getCurrentLocation(String libraryAlbumId) async {
    final response = await client
        .from(_tableName)
        .select()
        .eq('library_album_id', libraryAlbumId)
        .isFilter('removed_at', null)
        .order('detected_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;
    return AlbumLocation.fromJson(response);
  }

  /// Gets all current album locations for a library.
  ///
  /// Returns all albums that are currently present in crates
  /// (where removed_at is null).
  Future<List<AlbumLocation>> getCurrentLocationsForLibrary(
    String libraryId,
  ) async {
    // Query through library_albums to filter by library
    final response = await client
        .from(_tableName)
        .select('*, library_album:library_albums!inner(library_id)')
        .eq('library_album.library_id', libraryId)
        .isFilter('removed_at', null)
        .order('detected_at', ascending: false);

    return (response as List)
        .map((row) => AlbumLocation.fromJson(row))
        .toList();
  }

  /// Gets all current album locations for a specific device (crate).
  Future<List<AlbumLocation>> getAlbumsInCrate(String deviceId) async {
    final response = await client
        .from(_tableName)
        .select()
        .eq('device_id', deviceId)
        .isFilter('removed_at', null)
        .order('detected_at', ascending: false);

    return (response as List)
        .map((row) => AlbumLocation.fromJson(row))
        .toList();
  }

  /// Gets the location history for an album.
  ///
  /// Returns all location records including past locations.
  Future<List<AlbumLocation>> getLocationHistory(
    String libraryAlbumId, {
    int? limit,
  }) async {
    var query = client
        .from(_tableName)
        .select()
        .eq('library_album_id', libraryAlbumId)
        .order('detected_at', ascending: false);

    if (limit != null) {
      query = query.limit(limit);
    }

    final response = await query;

    return (response as List)
        .map((row) => AlbumLocation.fromJson(row))
        .toList();
  }

  /// Gets the last known location of an album.
  ///
  /// Returns the most recent location record, whether current or past.
  Future<AlbumLocation?> getLastKnownLocation(String libraryAlbumId) async {
    final response = await client
        .from(_tableName)
        .select()
        .eq('library_album_id', libraryAlbumId)
        .order('detected_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;
    return AlbumLocation.fromJson(response);
  }

  /// Gets albums with unknown locations in a library.
  ///
  /// Returns library album IDs that have never been detected in any crate.
  Future<List<String>> getAlbumsWithUnknownLocation(String libraryId) async {
    // Get all library album IDs in the library
    final libraryAlbumsResponse = await client
        .from('library_albums')
        .select('id')
        .eq('library_id', libraryId);

    final allAlbumIds = (libraryAlbumsResponse as List)
        .map((row) => row['id'] as String)
        .toSet();

    // Get all library album IDs that have ever been detected
    final locatedResponse = await client
        .from(_tableName)
        .select('library_album_id')
        .inFilter(
            'library_album_id', allAlbumIds.toList());

    final locatedIds = (locatedResponse as List)
        .map((row) => row['library_album_id'] as String)
        .toSet();

    // Return IDs that have never been located
    return allAlbumIds.difference(locatedIds).toList();
  }

  /// Gets location summary grouped by crate.
  ///
  /// Returns a map of device ID to list of album locations in that crate.
  Future<Map<String, List<AlbumLocation>>> getLocationsByCrate(
    String libraryId,
  ) async {
    final locations = await getCurrentLocationsForLibrary(libraryId);

    final result = <String, List<AlbumLocation>>{};
    for (final location in locations) {
      result.putIfAbsent(location.deviceId, () => []).add(location);
    }

    return result;
  }

  /// Gets the count of albums in each crate.
  Future<Map<String, int>> getCrateAlbumCounts(String libraryId) async {
    final locationsByCrate = await getLocationsByCrate(libraryId);

    return locationsByCrate.map(
      (deviceId, locations) => MapEntry(deviceId, locations.length),
    );
  }
}
