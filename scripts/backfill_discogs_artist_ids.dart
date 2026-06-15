// One-shot backfill: populate albums.discogs_artist_ids / .discogs_artist_names
// from the Discogs release detail endpoint for every row that has a discogs_id
// but no artist-id array yet.
//
// Run from the project root:
//   SUPABASE_URL=... \
//   SUPABASE_SERVICE_ROLE_KEY=... \
//   DISCOGS_TOKEN=... \
//     dart run scripts/backfill_discogs_artist_ids.dart
//
// Re-runnable: it only touches rows where discogs_artist_ids IS NULL, so
// partial runs resume cleanly. Rate-limited to ~60 req/min (Discogs
// authenticated cap). Pure "Various Artists" releases (artists == [194])
// are written as empty arrays so we don't try the artist page for id 194.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _discogsBaseUrl = 'https://api.discogs.com';
const _userAgent = 'SaturdayBackfill/1.0';
const _variousArtistsId = 194;
const _pageSize = 200;
const _minDiscogsInterval = Duration(milliseconds: 1100);

Future<void> main() async {
  final supabaseUrl = _envOrExit('SUPABASE_URL');
  final serviceKey = _envOrExit('SUPABASE_SERVICE_ROLE_KEY');
  final discogsToken = _envOrExit('DISCOGS_TOKEN');

  final client = http.Client();
  final supabase = _SupabaseRest(client, supabaseUrl, serviceKey);
  final discogs = _DiscogsClient(client, discogsToken);

  try {
    var totalProcessed = 0;
    var totalUpdated = 0;
    var totalSkipped = 0;
    var totalErrors = 0;
    final skipIds = <String>{}; // rows that errored this run — don't loop on them

    while (true) {
      // Updated rows drop out of the filter naturally, so we always re-query
      // from offset 0 and keep pulling until only previously-errored rows
      // remain.
      final rows = await supabase.fetchAlbumsNeedingBackfill(limit: _pageSize);
      final fresh = rows.where((r) => !skipIds.contains(r['id'])).toList();
      if (fresh.isEmpty) break;

      for (final row in fresh) {
        final id = row['id'] as String;
        final discogsId = row['discogs_id'] as int;

        try {
          final parsed = await discogs.fetchArtists(discogsId);
          if (parsed == null) {
            totalSkipped++;
            skipIds.add(id); // 404 — don't refetch
            stdout.writeln('skip $id (discogs $discogsId): release not found');
            continue;
          }

          await supabase.updateAlbumArtists(
            albumId: id,
            ids: parsed.ids,
            names: parsed.names,
          );
          totalUpdated++;
          stdout.writeln(
            'ok   $id (discogs $discogsId): '
            '${parsed.ids.length} artist(s) ${parsed.names.join(", ")}',
          );
        } catch (e) {
          totalErrors++;
          skipIds.add(id);
          stderr.writeln('err  $id (discogs $discogsId): $e');
        } finally {
          totalProcessed++;
        }
      }
    }

    stdout.writeln(
      '\nDone. processed=$totalProcessed '
      'updated=$totalUpdated skipped=$totalSkipped errors=$totalErrors',
    );
  } finally {
    client.close();
  }
}

String _envOrExit(String name) {
  final v = Platform.environment[name];
  if (v == null || v.isEmpty) {
    stderr.writeln('Missing required environment variable: $name');
    exit(2);
  }
  return v;
}

class _DiscogsArtists {
  final List<int> ids;
  final List<String> names;
  _DiscogsArtists(this.ids, this.names);
}

class _DiscogsClient {
  _DiscogsClient(this._client, this._token);

  final http.Client _client;
  final String _token;
  DateTime? _lastRequestAt;

  Future<_DiscogsArtists?> fetchArtists(int releaseId) async {
    await _respectRateLimit();

    final uri = Uri.parse('$_discogsBaseUrl/releases/$releaseId');
    final res = await _client.get(uri, headers: {
      'User-Agent': _userAgent,
      'Authorization': 'Discogs token=$_token',
    });

    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw HttpException(
        'Discogs ${res.statusCode}: ${res.body}',
        uri: uri,
      );
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final artists = data['artists'] as List<dynamic>? ?? const [];

    final ids = <int>[];
    final names = <String>[];
    for (final a in artists) {
      final map = a as Map<String, dynamic>;
      final id = map['id'] as int?;
      final rawName = map['name'] as String?;
      if (id == null || rawName == null) continue;
      ids.add(id);
      names.add(rawName.replaceAll(RegExp(r'\s*\(\d+\)\s*$'), ''));
    }

    // Pure "Various Artists" comp — write empty arrays so the row is marked
    // backfilled but doesn't link to a sinkhole artist page.
    if (ids.length == 1 && ids.first == _variousArtistsId) {
      return _DiscogsArtists(const [], const []);
    }

    return _DiscogsArtists(ids, names);
  }

  Future<void> _respectRateLimit() async {
    final last = _lastRequestAt;
    if (last != null) {
      final elapsed = DateTime.now().difference(last);
      if (elapsed < _minDiscogsInterval) {
        await Future.delayed(_minDiscogsInterval - elapsed);
      }
    }
    _lastRequestAt = DateTime.now();
  }
}

class _SupabaseRest {
  _SupabaseRest(this._client, String url, this._serviceKey)
      : _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  final http.Client _client;
  final String _baseUrl;
  final String _serviceKey;

  Map<String, String> get _headers => {
        'apikey': _serviceKey,
        'Authorization': 'Bearer $_serviceKey',
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
      };

  Future<List<Map<String, dynamic>>> fetchAlbumsNeedingBackfill({
    required int limit,
  }) async {
    final uri = Uri.parse('$_baseUrl/rest/v1/albums').replace(
      queryParameters: {
        'select': 'id,discogs_id',
        'discogs_id': 'not.is.null',
        'discogs_artist_ids': 'is.null',
        'order': 'created_at.asc',
        'limit': limit.toString(),
      },
    );

    final res = await _client.get(uri, headers: _headers);
    if (res.statusCode != 200) {
      throw HttpException(
        'Supabase select ${res.statusCode}: ${res.body}',
        uri: uri,
      );
    }
    return (jsonDecode(res.body) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<void> updateAlbumArtists({
    required String albumId,
    required List<int> ids,
    required List<String> names,
  }) async {
    final uri = Uri.parse('$_baseUrl/rest/v1/albums').replace(
      queryParameters: {'id': 'eq.$albumId'},
    );

    final res = await _client.patch(
      uri,
      headers: _headers,
      body: jsonEncode({
        'discogs_artist_ids': ids,
        'discogs_artist_names': names,
      }),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException(
        'Supabase patch ${res.statusCode}: ${res.body}',
        uri: uri,
      );
    }
  }
}
