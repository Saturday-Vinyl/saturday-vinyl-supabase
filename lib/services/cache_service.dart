import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/models/device.dart';

/// Keys for cached data in SharedPreferences.
class _CacheKeys {
  static const String libraryAlbums = 'cache.library_albums';
  static const String libraryAlbumsTimestamp = 'cache.library_albums_timestamp';
  static const String devices = 'cache.devices';
  static const String devicesTimestamp = 'cache.devices_timestamp';
  static const String currentLibraryId = 'cache.current_library_id';
}

/// Duration after which cached data is considered stale.
class CacheDuration {
  CacheDuration._();

  /// Library albums cache duration (1 hour).
  static const Duration libraryAlbums = Duration(hours: 1);

  /// Device status cache duration (5 minutes).
  static const Duration devices = Duration(minutes: 5);
}

/// Service for caching app data locally.
///
/// Uses SharedPreferences for JSON storage of library albums,
/// device status, and user preferences. The cached_network_image
/// package handles image caching automatically.
class CacheService {
  CacheService._();

  static final CacheService _instance = CacheService._();
  static CacheService get instance => _instance;

  SharedPreferences? _prefs;

  /// Initialize the cache service.
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();

    if (kDebugMode) {
      print('CacheService: Initialized');
    }
  }

  /// Get SharedPreferences instance, initializing if needed.
  Future<SharedPreferences> get _preferences async {
    if (_prefs == null) {
      await initialize();
    }
    return _prefs!;
  }

  // ============ Library Albums ============

  /// Cache library albums.
  Future<void> cacheLibraryAlbums(List<LibraryAlbum> albums) async {
    final prefs = await _preferences;

    try {
      final jsonList = albums.map((a) => a.toJson()).toList();
      final jsonString = jsonEncode(jsonList);

      await prefs.setString(_CacheKeys.libraryAlbums, jsonString);
      await prefs.setInt(
        _CacheKeys.libraryAlbumsTimestamp,
        DateTime.now().millisecondsSinceEpoch,
      );

      if (kDebugMode) {
        print('CacheService: Cached ${albums.length} library albums');
      }
    } catch (e) {
      if (kDebugMode) {
        print('CacheService: Error caching library albums: $e');
      }
    }
  }

  /// Get cached library albums.
  ///
  /// Returns null if no cached data or cache is expired.
  Future<List<LibraryAlbum>?> getCachedLibraryAlbums({
    bool ignoreExpiry = false,
  }) async {
    final prefs = await _preferences;

    // Check if cache exists.
    final jsonString = prefs.getString(_CacheKeys.libraryAlbums);
    if (jsonString == null) return null;

    // Check cache freshness.
    if (!ignoreExpiry) {
      final timestamp = prefs.getInt(_CacheKeys.libraryAlbumsTimestamp);
      if (timestamp == null) return null;

      final cachedAt = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final age = DateTime.now().difference(cachedAt);
      if (age > CacheDuration.libraryAlbums) {
        if (kDebugMode) {
          print('CacheService: Library albums cache expired (age: ${age.inMinutes}m)');
        }
        return null;
      }
    }

    // Parse and return cached data.
    try {
      final jsonList = jsonDecode(jsonString) as List;
      final albums = jsonList
          .map((json) => LibraryAlbum.fromJson(json as Map<String, dynamic>))
          .toList();

      if (kDebugMode) {
        print('CacheService: Retrieved ${albums.length} cached library albums');
      }

      return albums;
    } catch (e) {
      if (kDebugMode) {
        print('CacheService: Error parsing cached library albums: $e');
      }
      return null;
    }
  }

  /// Get the timestamp when library albums were last cached.
  Future<DateTime?> getLibraryAlbumsCacheTimestamp() async {
    final prefs = await _preferences;
    final timestamp = prefs.getInt(_CacheKeys.libraryAlbumsTimestamp);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Clear library albums cache.
  Future<void> clearLibraryAlbumsCache() async {
    final prefs = await _preferences;
    await prefs.remove(_CacheKeys.libraryAlbums);
    await prefs.remove(_CacheKeys.libraryAlbumsTimestamp);

    if (kDebugMode) {
      print('CacheService: Cleared library albums cache');
    }
  }

  // ============ Devices ============

  /// Cache device list.
  Future<void> cacheDevices(List<Device> devices) async {
    final prefs = await _preferences;

    try {
      final jsonList = devices.map((d) => d.toJson()).toList();
      final jsonString = jsonEncode(jsonList);

      await prefs.setString(_CacheKeys.devices, jsonString);
      await prefs.setInt(
        _CacheKeys.devicesTimestamp,
        DateTime.now().millisecondsSinceEpoch,
      );

      if (kDebugMode) {
        print('CacheService: Cached ${devices.length} devices');
      }
    } catch (e) {
      if (kDebugMode) {
        print('CacheService: Error caching devices: $e');
      }
    }
  }

  /// Get cached devices.
  ///
  /// Returns null if no cached data or cache is expired.
  Future<List<Device>?> getCachedDevices({bool ignoreExpiry = false}) async {
    final prefs = await _preferences;

    // Check if cache exists.
    final jsonString = prefs.getString(_CacheKeys.devices);
    if (jsonString == null) return null;

    // Check cache freshness.
    if (!ignoreExpiry) {
      final timestamp = prefs.getInt(_CacheKeys.devicesTimestamp);
      if (timestamp == null) return null;

      final cachedAt = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final age = DateTime.now().difference(cachedAt);
      if (age > CacheDuration.devices) {
        if (kDebugMode) {
          print('CacheService: Devices cache expired (age: ${age.inMinutes}m)');
        }
        return null;
      }
    }

    // Parse and return cached data.
    try {
      final jsonList = jsonDecode(jsonString) as List;
      final devices = jsonList
          .map((json) => Device.fromJson(json as Map<String, dynamic>))
          .toList();

      if (kDebugMode) {
        print('CacheService: Retrieved ${devices.length} cached devices');
      }

      return devices;
    } catch (e) {
      if (kDebugMode) {
        print('CacheService: Error parsing cached devices: $e');
      }
      return null;
    }
  }

  /// Get the timestamp when devices were last cached.
  Future<DateTime?> getDevicesCacheTimestamp() async {
    final prefs = await _preferences;
    final timestamp = prefs.getInt(_CacheKeys.devicesTimestamp);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Clear devices cache.
  Future<void> clearDevicesCache() async {
    final prefs = await _preferences;
    await prefs.remove(_CacheKeys.devices);
    await prefs.remove(_CacheKeys.devicesTimestamp);

    if (kDebugMode) {
      print('CacheService: Cleared devices cache');
    }
  }

  // ============ Current Library ID ============

  /// Cache the current library ID.
  Future<void> cacheCurrentLibraryId(String libraryId) async {
    final prefs = await _preferences;
    await prefs.setString(_CacheKeys.currentLibraryId, libraryId);
  }

  /// Get the cached current library ID.
  Future<String?> getCachedCurrentLibraryId() async {
    final prefs = await _preferences;
    return prefs.getString(_CacheKeys.currentLibraryId);
  }

  // ============ Clear All ============

  /// Clear all cached data.
  Future<void> clearAllCache() async {
    await clearLibraryAlbumsCache();
    await clearDevicesCache();

    if (kDebugMode) {
      print('CacheService: Cleared all cache');
    }
  }
}
