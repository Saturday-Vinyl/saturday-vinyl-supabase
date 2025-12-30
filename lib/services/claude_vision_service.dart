import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Result from Claude vision album identification.
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

  /// Whether the identification was successful.
  bool get isSuccessful =>
      artist != null &&
      artist!.isNotEmpty &&
      albumTitle != null &&
      albumTitle!.isNotEmpty;

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

/// Service for identifying album covers using Claude's vision capabilities.
class ClaudeVisionService {
  ClaudeVisionService({
    required this.apiKey,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client();

  static const String _baseUrl = 'https://api.anthropic.com/v1/messages';
  static const String _model = 'claude-sonnet-4-20250514';

  final String apiKey;
  final http.Client _client;

  /// Identifies an album from a photo of its cover.
  ///
  /// Takes the image as bytes and returns the identified artist and album title.
  Future<AlbumIdentificationResult> identifyAlbumCover(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
  }) async {
    final base64Image = base64Encode(imageBytes);

    final requestBody = {
      'model': _model,
      'max_tokens': 256,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': mimeType,
                'data': base64Image,
              },
            },
            {
              'type': 'text',
              'text': '''Identify this vinyl record album cover.

Return ONLY a JSON object with these fields:
- "artist": the artist or band name
- "album": the album title
- "confidence": "high", "medium", or "low"

If you cannot identify the album, return:
{"artist": null, "album": null, "confidence": "none"}

Do not include any other text, just the JSON object.''',
            },
          ],
        },
      ],
    };

    try {
      final response = await _client.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return _parseResponse(data);
      } else if (response.statusCode == 401) {
        throw ClaudeVisionException(
          'Invalid API key. Please check your ANTHROPIC_API_KEY.',
          response.statusCode,
        );
      } else if (response.statusCode == 429) {
        throw ClaudeVisionException(
          'Rate limit exceeded. Please try again later.',
          response.statusCode,
        );
      } else {
        throw ClaudeVisionException(
          'Claude API error: ${response.statusCode}',
          response.statusCode,
        );
      }
    } catch (e) {
      if (e is ClaudeVisionException) rethrow;
      throw ClaudeVisionException('Failed to identify album: $e', 0);
    }
  }

  /// Parses Claude's response into an AlbumIdentificationResult.
  AlbumIdentificationResult _parseResponse(Map<String, dynamic> data) {
    try {
      // Extract the text content from Claude's response
      final content = data['content'] as List<dynamic>?;
      if (content == null || content.isEmpty) {
        return AlbumIdentificationResult(rawResponse: jsonEncode(data));
      }

      final textBlock = content.firstWhere(
        (block) => block['type'] == 'text',
        orElse: () => null,
      );

      if (textBlock == null) {
        return AlbumIdentificationResult(rawResponse: jsonEncode(data));
      }

      final text = textBlock['text'] as String;

      // Try to parse as JSON
      // Sometimes Claude wraps JSON in markdown code blocks
      String jsonText = text.trim();
      if (jsonText.startsWith('```json')) {
        jsonText = jsonText.substring(7);
      } else if (jsonText.startsWith('```')) {
        jsonText = jsonText.substring(3);
      }
      if (jsonText.endsWith('```')) {
        jsonText = jsonText.substring(0, jsonText.length - 3);
      }
      jsonText = jsonText.trim();

      final parsed = jsonDecode(jsonText) as Map<String, dynamic>;

      return AlbumIdentificationResult(
        artist: parsed['artist'] as String?,
        albumTitle: parsed['album'] as String?,
        confidence: parsed['confidence'] as String?,
        rawResponse: text,
      );
    } catch (e) {
      // If JSON parsing fails, try to extract artist/album from raw text
      return AlbumIdentificationResult(
        rawResponse: jsonEncode(data),
      );
    }
  }

  /// Dispose of resources.
  void dispose() {
    _client.close();
  }
}

/// Exception for Claude Vision API errors.
class ClaudeVisionException implements Exception {
  final String message;
  final int statusCode;

  ClaudeVisionException(this.message, this.statusCode);

  @override
  String toString() => message;
}
