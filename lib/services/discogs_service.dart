import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:saturday_consumer_app/models/album.dart';
import 'package:saturday_consumer_app/models/track.dart';

/// Result from a Discogs search.
class DiscogsSearchResult {
  final int id;
  final String title;
  final String? coverImageUrl;
  final String? year;
  final List<String> formats;

  DiscogsSearchResult({
    required this.id,
    required this.title,
    this.coverImageUrl,
    this.year,
    this.formats = const [],
  });

  factory DiscogsSearchResult.fromJson(Map<String, dynamic> json) {
    return DiscogsSearchResult(
      id: json['id'] as int,
      title: json['title'] as String,
      coverImageUrl: json['cover_image'] as String?,
      year: json['year'] as String?,
      formats: (json['format'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  /// Extracts artist and album title from the combined title.
  /// Discogs format: "Artist - Album Title"
  String get artist {
    final parts = title.split(' - ');
    return parts.isNotEmpty ? parts[0].trim() : 'Unknown Artist';
  }

  String get albumTitle {
    final parts = title.split(' - ');
    return parts.length > 1 ? parts.sublist(1).join(' - ').trim() : title;
  }
}

/// Service for interacting with the Discogs API.
///
/// Handles searching for albums, looking up by barcode, and retrieving
/// full album details.
class DiscogsService {
  DiscogsService({
    this.userAgent = 'SaturdayApp/1.0',
    this.personalAccessToken,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client();

  static const String _baseUrl = 'https://api.discogs.com';

  final String userAgent;
  final String? personalAccessToken;
  final http.Client _client;

  /// Rate limiting: Discogs allows 60 requests per minute for authenticated,
  /// 25 for unauthenticated.
  DateTime? _lastRequestTime;
  static const _minRequestInterval = Duration(milliseconds: 1000);

  /// Search for releases by query string.
  Future<List<DiscogsSearchResult>> search(
    String query, {
    int page = 1,
    int perPage = 20,
  }) async {
    if (query.trim().isEmpty) return [];

    await _respectRateLimit();

    final uri = Uri.parse('$_baseUrl/database/search').replace(
      queryParameters: {
        'q': query,
        'type': 'release',
        'format': 'Vinyl',
        'page': page.toString(),
        'per_page': perPage.toString(),
      },
    );

    final response = await _makeRequest(uri);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>? ?? [];

    return results
        .map((r) => DiscogsSearchResult.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Search for a release by barcode.
  Future<List<DiscogsSearchResult>> searchByBarcode(String barcode) async {
    if (barcode.trim().isEmpty) return [];

    await _respectRateLimit();

    final uri = Uri.parse('$_baseUrl/database/search').replace(
      queryParameters: {
        'barcode': barcode,
        'type': 'release',
      },
    );

    final response = await _makeRequest(uri);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>? ?? [];

    return results
        .map((r) => DiscogsSearchResult.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Get full details for a release by Discogs ID.
  Future<Album?> getRelease(int releaseId) async {
    await _respectRateLimit();

    final uri = Uri.parse('$_baseUrl/releases/$releaseId');
    final response = await _makeRequest(uri);
    final data = jsonDecode(response.body) as Map<String, dynamic>;

    return _parseReleaseToAlbum(data, releaseId);
  }

  /// Parse Discogs release response into an Album model.
  Album? _parseReleaseToAlbum(Map<String, dynamic> data, int releaseId) {
    try {
      // Extract artist(s)
      final artists = data['artists'] as List<dynamic>?;
      final artistName = artists?.isNotEmpty == true
          ? (artists![0]['name'] as String?)
                  ?.replaceAll(RegExp(r'\s*\(\d+\)\s*$'), '') ??
              'Unknown Artist'
          : 'Unknown Artist';

      // Extract tracks
      final tracklist = data['tracklist'] as List<dynamic>? ?? [];
      final tracks = tracklist
          .where((t) => t['type_'] == 'track' || t['type_'] == null)
          .map((t) => Track(
                position: t['position'] as String? ?? '',
                title: t['title'] as String? ?? 'Unknown Track',
                durationSeconds: _parseDuration(t['duration'] as String?),
              ))
          .toList();

      // Extract genres and styles
      final genres =
          (data['genres'] as List<dynamic>?)?.cast<String>().toList() ?? [];
      final styles =
          (data['styles'] as List<dynamic>?)?.cast<String>().toList() ?? [];

      // Extract labels
      final labels = data['labels'] as List<dynamic>?;
      final labelName =
          labels?.isNotEmpty == true ? labels![0]['name'] as String? : null;

      // Get best image
      final images = data['images'] as List<dynamic>?;
      String? coverUrl;
      if (images != null && images.isNotEmpty) {
        // Prefer 'primary' type, fall back to first image
        final primary = images.firstWhere(
          (img) => img['type'] == 'primary',
          orElse: () => images.first,
        );
        coverUrl = primary['uri'] as String?;
      }

      final now = DateTime.now();

      return Album(
        id: '', // Will be assigned by database
        discogsId: releaseId,
        title: data['title'] as String? ?? 'Unknown Album',
        artist: artistName,
        year: data['year'] as int?,
        genres: genres,
        styles: styles,
        label: labelName,
        coverImageUrl: coverUrl,
        tracks: tracks,
        createdAt: now,
        updatedAt: now,
      );
    } catch (e) {
      return null;
    }
  }

  /// Parse duration string "MM:SS" to seconds.
  int? _parseDuration(String? duration) {
    if (duration == null || duration.isEmpty) return null;

    final parts = duration.split(':');
    if (parts.length != 2) return null;

    try {
      final minutes = int.parse(parts[0]);
      final seconds = int.parse(parts[1]);
      return minutes * 60 + seconds;
    } catch (_) {
      return null;
    }
  }

  /// Make an HTTP request with proper headers.
  Future<http.Response> _makeRequest(Uri uri) async {
    final headers = {
      'User-Agent': userAgent,
      'Accept': 'application/json',
    };

    if (personalAccessToken != null) {
      headers['Authorization'] = 'Discogs token=$personalAccessToken';
    }

    final response = await _client.get(uri, headers: headers);

    if (response.statusCode == 429) {
      throw DiscogsRateLimitException('Rate limit exceeded. Please try again.');
    }

    if (response.statusCode != 200) {
      throw DiscogsApiException(
        'Discogs API error: ${response.statusCode}',
        response.statusCode,
      );
    }

    _lastRequestTime = DateTime.now();
    return response;
  }

  /// Wait if necessary to respect rate limits.
  Future<void> _respectRateLimit() async {
    if (_lastRequestTime != null) {
      final elapsed = DateTime.now().difference(_lastRequestTime!);
      if (elapsed < _minRequestInterval) {
        await Future.delayed(_minRequestInterval - elapsed);
      }
    }
  }

  /// Dispose of resources.
  void dispose() {
    _client.close();
  }
}

/// Exception for Discogs API errors.
class DiscogsApiException implements Exception {
  final String message;
  final int statusCode;

  DiscogsApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}

/// Exception for rate limit errors.
class DiscogsRateLimitException implements Exception {
  final String message;

  DiscogsRateLimitException(this.message);

  @override
  String toString() => message;
}
