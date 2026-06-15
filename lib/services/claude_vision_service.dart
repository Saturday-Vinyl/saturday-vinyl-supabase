import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result from album-cover identification.
class AlbumIdentificationResult {
  final String? artist;
  final String? albumTitle;
  final String? confidence;
  final String? rawResponse;

  AlbumIdentificationResult({
    this.artist,
    this.albumTitle,
    this.confidence,
    this.rawResponse,
  });

  /// Whether the identification was successful enough to act on.
  bool get isSuccessful =>
      artist != null &&
      artist!.isNotEmpty &&
      albumTitle != null &&
      albumTitle!.isNotEmpty &&
      confidence != 'none';

  /// Returns a search query combining artist and album.
  String get searchQuery {
    if (artist != null && albumTitle != null) {
      return '$artist $albumTitle';
    } else if (artist != null) {
      return artist!;
    } else if (albumTitle != null) {
      return albumTitle!;
    }
    return '';
  }
}

/// Identifies vinyl album covers from photos.
///
/// Calls the `identify-album-cover` edge function, which proxies the request
/// to Anthropic's vision API server-side. The model ID, prompt, and API key
/// all live in the edge function — none of those require a mobile app
/// release to change.
class ClaudeVisionService {
  ClaudeVisionService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const String _functionName = 'identify-album-cover';

  final SupabaseClient _client;

  /// Identifies an album from a photo of its cover.
  Future<AlbumIdentificationResult> identifyAlbumCover(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
  }) async {
    final base64Image = base64Encode(imageBytes);

    try {
      final response = await _client.functions.invoke(
        _functionName,
        body: {
          'image_base64': base64Image,
          'mime_type': mimeType,
        },
      );

      final status = response.status;
      final data = response.data;

      if (status != 200) {
        final message = data is Map<String, dynamic>
            ? data['error']?.toString() ?? 'Status $status'
            : 'Status $status';
        throw ClaudeVisionException(message, status);
      }

      if (data is! Map<String, dynamic>) {
        throw ClaudeVisionException(
          'Unexpected response shape from vision service',
          status,
        );
      }

      return AlbumIdentificationResult(
        artist: data['artist'] as String?,
        albumTitle: data['album'] as String?,
        confidence: data['confidence'] as String?,
        rawResponse: jsonEncode(data),
      );
    } on ClaudeVisionException {
      rethrow;
    } catch (e) {
      throw ClaudeVisionException('Failed to identify album: $e', 0);
    }
  }
}

/// Exception for vision identification errors.
class ClaudeVisionException implements Exception {
  final String message;
  final int statusCode;

  ClaudeVisionException(this.message, this.statusCode);

  @override
  String toString() => message;
}
